# Stress tests for the best benchmark model
#
# 1. Noise robustness: add Gaussian noise to the held-out test inputs (a
#    fraction of each feature's training standard deviation) and track accuracy
#    for the tuned Random Forest and the 1-NN baseline. Real sensor and lab
#    readings are noisy; a model that only works on clean benchmark values is
#    not useful in practice.
# 2. Feature ablation: retrain the Random Forest without each feature in turn,
#    to see which measurements the recommendation actually depends on.
#
# Requires modelling/results/best_model.rds from modelling/benchmark.R.
# Run from the repository root:  Rscript modelling/stress_test.R

suppressPackageStartupMessages({
  library(tidymodels)
})
tidymodels_prefer()

out_dir <- file.path("modelling", "results")
n_threads <- max(1, parallel::detectCores())
n_repeats <- 20
noise_levels <- c(0, 0.05, 0.10, 0.20, 0.30, 0.50)

# Same data and split as benchmark.R (same seed, same call order)
set.seed(42)
crops <- read.csv(file.path("dataset", "Crop_recommendation_cleaned.csv")) |>
  mutate(label = factor(label))
split <- initial_split(crops, prop = 0.8, strata = label, pool = 0)
train <- training(split)
test  <- testing(split)
features <- setdiff(names(crops), "label")

best_model <- readRDS(file.path(out_dir, "best_model.rds"))
rf_engine <- extract_fit_engine(best_model)
cat("Loaded model:", class(rf_engine)[1], "| mtry =", rf_engine$mtry,
    "| min.node.size =", rf_engine$min.node.size, "\n")

# 1-NN baseline on standardised features (scaled with training statistics)
train_mean <- sapply(train[features], mean)
train_sd   <- sapply(train[features], sd)
scale_x <- function(df) sweep(sweep(as.matrix(df[features]), 2, train_mean), 2, train_sd, "/")
predict_1nn <- function(df) class::knn(scale_x(train), scale_x(df), cl = train$label, k = 1)

add_noise <- function(df, level) {
  if (level == 0) return(df)
  for (f in features) {
    noisy <- df[[f]] + rnorm(nrow(df), 0, level * train_sd[[f]])
    # N, P, K are whole numbers in soil reports; keep their integer type
    df[[f]] <- if (is.integer(df[[f]])) as.integer(round(noisy)) else noisy
  }
  df
}

# ----------------------------------------------------------------------------
# 1. Noise robustness
# ----------------------------------------------------------------------------
cat("\nNoise robustness (", n_repeats, "repeats per level)\n", sep = "")
set.seed(123)
noise_runs <- map_dfr(noise_levels, function(level) {
  reps <- if (level == 0) 1 else n_repeats
  map_dfr(seq_len(reps), function(r) {
    noisy <- add_noise(test, level)
    tibble(
      noise = level,
      repeat_id = r,
      random_forest = mean(predict(best_model, noisy)$.pred_class == test$label),
      baseline_1nn  = mean(predict_1nn(noisy) == test$label)
    )
  })
})

noise_summary <- noise_runs |>
  pivot_longer(c(random_forest, baseline_1nn), names_to = "model", values_to = "accuracy") |>
  group_by(noise, model) |>
  summarise(mean_accuracy = mean(accuracy), sd_accuracy = sd(accuracy),
            low = quantile(accuracy, 0.05), high = quantile(accuracy, 0.95),
            .groups = "drop")
write.csv(noise_summary |> mutate(across(where(is.double), \(x) round(x, 4))),
          file.path(out_dir, "noise_robustness.csv"), row.names = FALSE)
print(noise_summary |> select(noise, model, mean_accuracy) |>
        pivot_wider(names_from = model, values_from = mean_accuracy) |>
        mutate(across(-noise, \(x) round(x, 4))) |> as.data.frame(), row.names = FALSE)

noise_plot <- ggplot(noise_summary,
                     aes(noise * 100, mean_accuracy * 100, colour = model)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  geom_errorbar(aes(ymin = low * 100, ymax = high * 100), width = 1) +
  scale_colour_manual(values = c(random_forest = "#2a6f97", baseline_1nn = "#c96b2c"),
                      labels = c(random_forest = "Random Forest (tuned)",
                                 baseline_1nn = "1-NN baseline")) +
  labs(title = "Test accuracy under input noise",
       subtitle = "Gaussian noise as % of each feature's standard deviation; bars = 5th-95th percentile over 20 runs",
       x = "Noise level (% of feature SD)", y = "Accuracy (%)", colour = NULL) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")
ggsave(file.path(out_dir, "noise_robustness.png"), noise_plot, width = 8, height = 5, dpi = 120)

# ----------------------------------------------------------------------------
# 2. Feature ablation (leave one feature out, same hyperparameters)
# ----------------------------------------------------------------------------
cat("\nFeature ablation\n")
fit_rf <- function(cols) {
  ranger::ranger(
    x = train[cols], y = train$label,
    num.trees = 500,
    mtry = min(rf_engine$mtry, length(cols)),
    min.node.size = rf_engine$min.node.size,
    num.threads = n_threads, seed = 42
  )
}
rf_accuracy <- function(cols) {
  fit <- fit_rf(cols)
  mean(predict(fit, test[cols], num.threads = n_threads)$predictions == test$label)
}

all_acc <- rf_accuracy(features)
ablation <- tibble(removed = features) |>
  mutate(accuracy = map_dbl(removed, \(f) rf_accuracy(setdiff(features, f))),
         drop_points = (all_acc - accuracy) * 100) |>
  arrange(desc(drop_points))
ablation <- bind_rows(tibble(removed = "(none)", accuracy = all_acc, drop_points = 0), ablation)
write.csv(ablation |> mutate(across(where(is.double), \(x) round(x, 4))),
          file.path(out_dir, "feature_ablation.csv"), row.names = FALSE)
print(ablation |> mutate(across(where(is.double), \(x) round(x, 4))) |> as.data.frame(),
      row.names = FALSE)

ablation_plot <- ablation |>
  filter(removed != "(none)") |>
  ggplot(aes(drop_points, reorder(removed, drop_points))) +
  geom_col(fill = "#2a6f97") +
  geom_text(aes(label = sprintf("%.1f", drop_points)), hjust = -0.2, size = 3.5) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(title = "Accuracy lost when a feature is removed",
       subtitle = sprintf("Random Forest retrained without each feature; all features: %.2f%%", all_acc * 100),
       x = "Accuracy drop (percentage points)", y = NULL) +
  theme_minimal(base_size = 12)
ggsave(file.path(out_dir, "feature_ablation.png"), ablation_plot, width = 8, height = 4.5, dpi = 120)

cat("\nSaved stress-test results to", out_dir, "\n")
