# Provenance audit: how the Kaggle Crop Recommendation dataset was built
#
# Shows, from the dataset author's own source files (dataset/external/harvestify/), that
#   1. our raw file is the original 2,200 rows plus only the injected defects,
#   2. the temperature, humidity and rainfall columns were copied from cpdata.csv,
#   3. the N, P, K columns are random integers drawn around ONE recommended
#      fertilizer dose per crop (FertilizerData.csv), not soil measurements.
#
# Run from the repository root:  Rscript modelling/provenance_audit.R

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

ext <- file.path("dataset", "external", "harvestify")
out_dir <- file.path("modelling", "results")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

original <- read.csv(file.path(ext, "crop_recommendation_original.csv"))
raw      <- read.csv(file.path("dataset", "Crop_recommendation.csv"))
cleaned  <- read.csv(file.path("dataset", "Crop_recommendation_cleaned.csv"))
climate  <- read.csv(file.path(ext, "cpdata.csv"))
fert     <- read.csv(file.path(ext, "FertilizerData.csv")) |>
  transmute(label = tolower(trimws(Crop)), fert_N = N, fert_P = P, fert_K = K)

# Compare at 4 decimals: write.csv keeps 15 significant digits, so values can
# round differently at the 6th decimal after a save and reload
row_key <- function(df) {
  with(df, paste(N, P, K, round(temperature, 4), round(humidity, 4),
                 round(ph, 4), round(rainfall, 4), label))
}

# ----------------------------------------------------------------------------
# 1. Our raw file vs the original
# ----------------------------------------------------------------------------
cat("== 1. Raw file vs original Kaggle data ==\n")
complete_raw <- raw[complete.cases(raw), ]
cat("Original rows:", nrow(original), "\n")
cat("Raw rows:", nrow(raw), "(", sum(!complete.cases(raw)), "with a blanked value )\n")
cat("Distinct complete raw rows:", length(unique(row_key(complete_raw))), "\n")
cat("Raw rows not in the original:", sum(!row_key(complete_raw) %in% row_key(original)), "\n")
cat("Cleaned data identical to original (as a set):",
    setequal(row_key(cleaned), row_key(original)), "\n\n")

# ----------------------------------------------------------------------------
# 2. Climate columns copied from cpdata.csv
# ----------------------------------------------------------------------------
cat("== 2. Climate columns ==\n")
climate_key <- function(df) with(df, paste(round(temperature, 4), round(humidity, 4), round(rainfall, 4)))
copied <- climate_key(original) %in% climate_key(climate)
cat("Rows whose temperature + humidity + rainfall appear verbatim in cpdata.csv:",
    sum(copied), "of", nrow(original), sprintf("(%.1f%%)\n\n", 100 * mean(copied)))

# ----------------------------------------------------------------------------
# 3. N, P, K = fertilizer dose + uniform random offset
# ----------------------------------------------------------------------------
cat("== 3. N, P, K vs recommended fertilizer dose ==\n")
offsets <- original |>
  inner_join(fert, by = "label") |>
  transmute(label, N = N - fert_N, P = P - fert_P, K = K - fert_K) |>
  pivot_longer(c(N, P, K), names_to = "nutrient", values_to = "offset")

cat("Crops matched to a fertilizer row:", n_distinct(offsets$label), "of",
    n_distinct(original$label), "\n")
offset_ranges <- offsets |>
  group_by(nutrient) |>
  summarise(min_offset = min(offset), max_offset = max(offset),
            distinct_values = n_distinct(offset), .groups = "drop")
print(as.data.frame(offset_ranges), row.names = FALSE)

# Uniformity: chi-squared test of the offset counts against a flat distribution
uniformity <- offsets |>
  group_by(nutrient) |>
  summarise(p_value = suppressWarnings(chisq.test(table(offset))$p.value), .groups = "drop")
cat("\nChi-squared test against a uniform distribution (high p = consistent with uniform):\n")
print(as.data.frame(uniformity |> mutate(p_value = signif(p_value, 3))), row.names = FALSE)

write.csv(left_join(offset_ranges, uniformity, by = "nutrient"),
          file.path(out_dir, "provenance_npk_offsets.csv"), row.names = FALSE)

offset_plot <- ggplot(offsets, aes(offset)) +
  geom_histogram(binwidth = 1, fill = "#2a6f97", colour = "white") +
  facet_wrap(~nutrient, scales = "free_x",
             labeller = as_labeller(c(N = "N: dose ± 20", P = "P: dose −5 to +20", K = "K: dose ± 5"))) +
  labs(title = "Kaggle N, P, K values minus each crop's recommended fertilizer dose",
       subtitle = "Flat, hard-edged ranges: random integers around one value per crop, not soil measurements",
       x = "Offset from fertilizer dose", y = "Rows") +
  theme_minimal(base_size = 12)
ggsave(file.path(out_dir, "provenance_npk_offsets.png"), offset_plot, width = 10, height = 4, dpi = 120)

cat("\nSaved audit outputs to", out_dir, "\n")
