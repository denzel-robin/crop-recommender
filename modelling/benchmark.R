# Model benchmark for the crop recommendation dataset
#
# Compares 6 classifiers (k-NN via class::knn) with stratified 10-fold cross-validation (tuning on the
# training set) and a held-out 20% test set. A tuning-free 1-nearest-neighbour
# model is the baseline: on this dataset it is already very strong, so any
# model has to be judged against it, not against 0%.
#
# Run from the repository root:  Rscript modelling/benchmark.R
# Outputs go to modelling/results/.

suppressPackageStartupMessages({
  library(tidymodels)
})
tidymodels_prefer()

# Tune models in parallel across CPU cores
future::plan(future::multisession, workers = max(1, parallel::detectCores() - 1))

set.seed(42)
out_dir <- file.path("modelling", "results")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ----------------------------------------------------------------------------
# Data and split
# ----------------------------------------------------------------------------
crops <- read.csv(file.path("dataset", "Crop_recommendation_cleaned.csv")) |>
  mutate(label = factor(label))
cat("Rows:", nrow(crops), "| crops:", nlevels(crops$label), "\n")

# pool = 0: every crop is only 4.5% of the data, and rsample would otherwise
# merge such small strata and silently fall back to an unstratified split
split <- initial_split(crops, prop = 0.8, strata = label, pool = 0)
train <- training(split)
test  <- testing(split)
folds <- vfold_cv(train, v = 10, strata = label, pool = 0)

base_recipe <- recipe(label ~ ., data = train) |>
  step_normalize(all_numeric_predictors())

metrics <- metric_set(accuracy, f_meas)  # f_meas is macro-averaged for multiclass

# ----------------------------------------------------------------------------
# Models
# ----------------------------------------------------------------------------
models <- list(
  logistic = multinom_reg() |>
    set_engine("nnet", MaxNWts = 5000) |> set_mode("classification"),
  svm_rbf = svm_rbf(cost = tune(), rbf_sigma = tune()) |>
    set_engine("kernlab") |> set_mode("classification"),
  decision_tree = decision_tree(cost_complexity = tune(), tree_depth = tune()) |>
    set_engine("rpart") |> set_mode("classification"),
  random_forest = rand_forest(mtry = tune(), min_n = tune(), trees = 500) |>
    set_engine("ranger", importance = "permutation") |> set_mode("classification"),
  xgboost = boost_tree(trees = 500, learn_rate = tune(), tree_depth = tune()) |>
    set_engine("xgboost") |> set_mode("classification")
)

wf_set <- workflow_set(
  preproc = list(std = base_recipe),
  models = models
)

# ----------------------------------------------------------------------------
# Cross-validation and tuning
# ----------------------------------------------------------------------------
cat("Tuning", length(models), "models with 10-fold CV...\n")
cv_results <- workflow_map(
  wf_set,
  fn = "tune_grid",
  resamples = folds,
  grid = 10,
  metrics = metrics,
  control = control_grid(save_pred = FALSE, verbose = FALSE),
  seed = 42
)

cv_summary <- rank_results(cv_results, rank_metric = "accuracy", select_best = TRUE) |>
  select(wflow_id, .metric, mean, std_err) |>
  pivot_wider(names_from = .metric, values_from = c(mean, std_err)) |>
  arrange(desc(mean_accuracy))

# ----------------------------------------------------------------------------
# Refit the best configuration of each model on the full training set,
# evaluate once on the untouched test set
# ----------------------------------------------------------------------------
test_results <- map_dfr(cv_results$wflow_id, function(id) {
  best <- cv_results |>
    extract_workflow_set_result(id) |>
    select_best(metric = "accuracy")
  fitted <- cv_results |>
    extract_workflow(id) |>
    finalize_workflow(best) |>
    last_fit(split, metrics = metrics)
  collect_metrics(fitted) |>
    select(.metric, .estimate) |>
    pivot_wider(names_from = .metric, values_from = .estimate) |>
    mutate(wflow_id = id, fit = list(fitted))
})

results <- cv_summary |>
  left_join(test_results |> select(-fit), by = "wflow_id") |>
  transmute(
    model = sub("^std_", "", wflow_id),
    cv_accuracy = round(mean_accuracy, 4),
    cv_accuracy_se = round(std_err_accuracy, 4),
    cv_macro_f1 = round(mean_f_meas, 4),
    test_accuracy = round(accuracy, 4),
    test_macro_f1 = round(f_meas, 4)
  ) |>
  arrange(desc(test_accuracy), desc(cv_accuracy))

# ----------------------------------------------------------------------------
# k-nearest-neighbour models via class::knn (k = 1 is the tuning-free baseline;
# k is otherwise chosen by the same 10-fold CV)
# ----------------------------------------------------------------------------
knn_eval <- function(fit_df, eval_df, k) {
  prep_rec <- prep(base_recipe, training = fit_df)
  x_fit  <- bake(prep_rec, fit_df) |> select(-label)
  x_eval <- bake(prep_rec, eval_df) |> select(-label)
  pred <- class::knn(x_fit, x_eval, cl = fit_df$label, k = k)
  tibble(truth = eval_df$label, estimate = pred)
}
knn_cv <- function(k) {
  per_fold <- map_dfr(folds$splits, function(s) {
    knn_eval(analysis(s), assessment(s), k) |>
      metrics(truth = truth, estimate = estimate)
  })
  per_fold |>
    group_by(.metric) |>
    summarise(mean = mean(.estimate), se = sd(.estimate) / sqrt(n()), .groups = "drop")
}
knn_row <- function(name, k) {
  cv <- knn_cv(k)
  te <- knn_eval(train, test, k) |> metrics(truth = truth, estimate = estimate)
  tibble(
    model = name,
    cv_accuracy = round(cv$mean[cv$.metric == "accuracy"], 4),
    cv_accuracy_se = round(cv$se[cv$.metric == "accuracy"], 4),
    cv_macro_f1 = round(cv$mean[cv$.metric == "f_meas"], 4),
    test_accuracy = round(te$.estimate[te$.metric == "accuracy"], 4),
    test_macro_f1 = round(te$.estimate[te$.metric == "f_meas"], 4)
  )
}
set.seed(42)
k_grid <- c(1, 3, 5, 7, 9, 15, 21)
k_cv_acc <- map_dbl(k_grid, function(k) knn_cv(k)$mean[1])
best_k <- k_grid[which.max(k_cv_acc)]
knn_rows <- knn_row("baseline_1nn", 1)
if (best_k != 1) knn_rows <- bind_rows(knn_rows, knn_row(paste0("knn_k", best_k), best_k))
results <- bind_rows(results, knn_rows) |>
  arrange(desc(test_accuracy), desc(cv_accuracy))

write.csv(results, file.path(out_dir, "benchmark_results.csv"), row.names = FALSE)
cat("\nResults (sorted by test accuracy):\n")
print(as.data.frame(results), row.names = FALSE)

# ----------------------------------------------------------------------------
# Best model: confusion matrix, feature importance, saved model
# ----------------------------------------------------------------------------
best_id <- paste0("std_", results$model[!grepl("^(baseline_1nn|knn_k)", results$model)][1])
best_fit <- test_results$fit[[which(test_results$wflow_id == best_id)]]
cat("\nBest model:", sub("^std_", "", best_id), "\n")

preds <- collect_predictions(best_fit)
cm_plot <- conf_mat(preds, truth = label, estimate = .pred_class) |>
  autoplot(type = "heatmap") +
  labs(title = paste("Test-set confusion matrix:", sub("^std_", "", best_id))) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(out_dir, "confusion_matrix.png"), cm_plot, width = 10, height = 9, dpi = 120)

misclassified <- preds |>
  filter(label != .pred_class) |>
  count(label, .pred_class, name = "n", sort = TRUE)
write.csv(misclassified, file.path(out_dir, "misclassified_pairs.csv"), row.names = FALSE)
cat("Misclassified test rows:", sum(misclassified$n), "of", nrow(preds), "\n")

final_model <- extract_workflow(best_fit)
saveRDS(final_model, file.path(out_dir, "best_model.rds"))

if (best_id == "std_random_forest") {
  importance <- extract_fit_engine(final_model)$variable.importance
  importance <- sort(importance, decreasing = TRUE)
  write.csv(data.frame(feature = names(importance), importance = unname(importance)),
            file.path(out_dir, "feature_importance.csv"), row.names = FALSE)
  cat("\nPermutation importance:\n")
  print(round(importance, 4))
}

cat("\nSaved results to", out_dir, "\n")
