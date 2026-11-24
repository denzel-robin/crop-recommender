# Real-data validation on Soil Health Card records (Pune, Maharashtra)
#
# Data: "Soil Nutrient Dataset for Crop Advice" (Mendeley Data, CC BY 4.0),
# see dataset/external/SOURCES.md. Each row is one (soil test, advised crop)
# pair, so one soil test appears once per crop it was advised for, often with
# repeated rows. The honest unit of analysis is the soil test ("card"), and
# the task is to rank the crops advised for it (multi-label), not to predict
# a single crop.
#
# Evaluation is grouped by card (no card in both train and test), plus a
# harder leave-one-village-out test of generalisation to a new place.
#
# Run from the repository root:  Rscript modelling/soil_health_card.R

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(ggplot2)
  library(readxl)
})

shc_dir <- file.path("dataset", "external", "soil_health_card")
out_dir <- file.path("modelling", "results")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
n_threads <- max(1, parallel::detectCores())
set.seed(42)

# ----------------------------------------------------------------------------
# Load and tidy
# ----------------------------------------------------------------------------
xlsx <- file.path(shc_dir, "Crop Adv data", "Cat data all pub.xlsx")
if (!file.exists(xlsx)) {
  stop("Missing ", xlsx, ": download and unzip the dataset as described in dataset/external/SOURCES.md")
}
raw <- read_excel(xlsx, .name_repair = "unique_quiet")
names(raw) <- c("pH", "pH_class", "OC", "OC_class", "N", "N_class", "P", "K", "S",
                "Zn", "B", "Fe", "Mn", "Cu", "crop", "district", "sub_district",
                "village", "year")
shc <- raw |> filter(!is.na(crop), !is.na(village))
write.csv(shc, file.path(shc_dir, "soil_health_card.csv"), row.names = FALSE)

# Ordinal encoding of the soil-test categories (VL < L < M < H < VH)
level_map <- c(VL = 0, L = 1, M = 2, H = 3, VH = 4)
cat_cols <- c("P", "K", "S", "Zn", "B", "Fe", "Mn", "Cu")
num_cols <- c("pH", "OC", "N")
soil_features <- c(num_cols, cat_cols)

shc <- shc |>
  mutate(across(all_of(cat_cols), \(x) unname(level_map[x]))) |>
  mutate(card_id = as.integer(factor(paste(pH, OC, N, P, K, S, Zn, B, Fe, Mn, Cu,
                                           village, year))))

cards <- shc |>
  group_by(card_id, village, year, across(all_of(soil_features))) |>
  summarise(rows = n(), crops = list(sort(unique(crop))), .groups = "drop")
all_crops <- sort(unique(shc$crop))

cat("Rows:", nrow(shc), "| distinct soil tests (cards):", nrow(cards),
    "| crops:", length(all_crops), "| villages:", n_distinct(cards$village), "\n")
cat("Advised crops per card: median", median(lengths(cards$crops)),
    "(range", paste(range(lengths(cards$crops)), collapse = "-"), ")\n")

# Wide 0/1 label matrix, one column per crop
labels <- map_dfc(all_crops, \(cr) setNames(tibble(as.integer(map_lgl(cards$crops, \(s) cr %in% s))), cr))

# ----------------------------------------------------------------------------
# Scorers: each returns a (test cards x crops) score matrix
# ----------------------------------------------------------------------------
score_popularity <- function(train_idx, test_idx) {
  freq <- colMeans(labels[train_idx, ])
  matrix(freq, nrow = length(test_idx), ncol = length(all_crops), byrow = TRUE,
         dimnames = list(NULL, all_crops))
}

score_village <- function(train_idx, test_idx) {
  overall <- colMeans(labels[train_idx, ])
  t(sapply(test_idx, function(i) {
    same <- train_idx[cards$village[train_idx] == cards$village[i]]
    if (length(same) == 0) overall else colMeans(labels[same, ]) + 1e-6 * overall
  })) |> `colnames<-`(all_crops)
}

score_rf <- function(features) {
  function(train_idx, test_idx) {
    x_train <- cards[train_idx, features]
    x_test  <- cards[test_idx, features]
    if ("village" %in% features) {
      lv <- sort(unique(cards$village))
      x_train$village <- factor(x_train$village, levels = lv)
      x_test$village  <- factor(x_test$village, levels = lv)
    }
    sapply(all_crops, function(cr) {
      y <- labels[[cr]][train_idx]
      if (length(unique(y)) < 2) return(rep(mean(y), length(test_idx)))
      fit <- ranger::ranger(x = as.data.frame(x_train), y = factor(y, levels = c(0, 1)),
                            probability = TRUE, num.trees = 300, min.node.size = 3,
                            num.threads = n_threads, seed = 42)
      predict(fit, as.data.frame(x_test), num.threads = n_threads)$predictions[, "1"]
    })
  }
}

# ----------------------------------------------------------------------------
# Ranking metrics per card, averaged over cards
# ----------------------------------------------------------------------------
rank_metrics <- function(scores, test_idx, k = 3) {
  map_dfr(seq_along(test_idx), function(j) {
    truth <- cards$crops[[test_idx[j]]]
    s <- scores[j, ] + runif(length(all_crops), 0, 1e-9)  # random tie-break
    ranked <- names(sort(s, decreasing = TRUE))
    topk <- ranked[seq_len(k)]
    tibble(hit_at_1 = as.numeric(ranked[1] %in% truth),
           precision_at_3 = mean(topk %in% truth),
           recall_at_3 = sum(topk %in% truth) / length(truth))
  })
}

evaluate <- function(folds, scorers) {
  map_dfr(names(scorers), function(name) {
    map_dfr(folds, function(test_idx) {
      train_idx <- setdiff(seq_len(nrow(cards)), test_idx)
      rank_metrics(scorers[[name]](train_idx, test_idx), test_idx)
    }) |> summarise(across(everything(), mean)) |> mutate(model = name, .before = 1)
  })
}

scorers <- list(
  "Popularity (most common crops)" = score_popularity,
  "Village only (local popularity)" = score_village,
  "Soil only (Random Forest)" = score_rf(soil_features),
  "Soil + village (Random Forest)" = score_rf(c(soil_features, "village"))
)

# 10-fold CV grouped by card
card_folds <- split(sample(seq_len(nrow(cards))), rep(1:10, length.out = nrow(cards)))
cat("\n== 10-fold CV, grouped by soil test ==\n")
cv_results <- evaluate(card_folds, scorers) |> mutate(scheme = "Grouped by soil test")
print(as.data.frame(cv_results |> mutate(across(where(is.double), \(x) round(x, 3)))), row.names = FALSE)

# Leave one village out: can the model advise a village it has never seen?
village_folds <- split(seq_len(nrow(cards)), cards$village)
cat("\n== Leave one village out ==\n")
lovo_results <- evaluate(village_folds, scorers[c("Popularity (most common crops)",
                                                   "Soil only (Random Forest)")]) |>
  mutate(scheme = "Leave one village out")
print(as.data.frame(lovo_results |> mutate(across(where(is.double), \(x) round(x, 3)))), row.names = FALSE)

results <- bind_rows(cv_results, lovo_results) |>
  mutate(across(where(is.double), \(x) round(x, 4)))
write.csv(results, file.path(out_dir, "soil_health_card_results.csv"), row.names = FALSE)

# ----------------------------------------------------------------------------
# Leakage illustration: the naive single-label, row-level approach
# ----------------------------------------------------------------------------
# A random row split puts copies of the same soil test in train and test.
# The best any single-label model can do is the share of each card's most
# frequent crop, so report that ceiling next to the naive accuracy.
naive_split <- sample(nrow(shc), round(0.8 * nrow(shc)))
naive_fit <- ranger::ranger(x = as.data.frame(shc[naive_split, soil_features]),
                            y = factor(shc$crop[naive_split]), num.trees = 300,
                            num.threads = n_threads, seed = 42)
naive_acc <- mean(predict(naive_fit, as.data.frame(shc[-naive_split, soil_features]))$predictions ==
                    shc$crop[-naive_split])
ceiling_acc <- shc |> count(card_id, crop) |> group_by(card_id) |>
  summarise(best = max(n), total = sum(n), .groups = "drop") |>
  summarise(sum(best) / sum(total)) |> pull()
cat(sprintf("\nNaive row-level single-label accuracy: %.1f%% (ceiling for any single-label model: %.1f%%)\n",
            100 * naive_acc, 100 * ceiling_acc))
write.csv(tibble(naive_row_split_accuracy = round(naive_acc, 4),
                 single_label_ceiling = round(ceiling_acc, 4)),
          file.path(out_dir, "soil_health_card_naive.csv"), row.names = FALSE)

# ----------------------------------------------------------------------------
# Plot
# ----------------------------------------------------------------------------
plot_data <- results |>
  mutate(model = factor(model, levels = names(scorers)),
         scheme = factor(scheme, levels = c("Grouped by soil test", "Leave one village out")))
p <- ggplot(plot_data, aes(recall_at_3 * 100, model)) +
  geom_col(fill = "#2a6f97") +
  geom_text(aes(label = sprintf("%.0f%%", recall_at_3 * 100)), hjust = -0.15, size = 3.5) +
  facet_wrap(~scheme) +
  scale_x_continuous(limits = c(0, 100), expand = expansion(mult = c(0, 0.05))) +
  labs(title = "Real Soil Health Card data: share of advised crops found in the top 3",
       subtitle = sprintf("%d soil tests, %d crops, 8 villages near Pune; recall@3, higher is better",
                          nrow(cards), length(all_crops)),
       x = "Recall@3 (%)", y = NULL) +
  theme_minimal(base_size = 12)
ggsave(file.path(out_dir, "soil_health_card_results.png"), p, width = 10, height = 4, dpi = 120)

cat("\nSaved results to", out_dir, "\n")
