# Data Preprocessing Script for Crop Recommendation Dataset
# Handles duplicates and missing values.
#
# Order matters: duplicates are removed BEFORE imputation. Imputing first turns
# copies with a blanked value into "new" rows that survive de-duplication and
# inflate one class (previously rice ended up with 107 rows instead of 100).
#
# Run from the repository root:  Rscript dataset_cleaning/datasetClean.R

rm(list = ls())

input_file  <- file.path("dataset", "Crop_recommendation.csv")
output_file <- file.path("dataset", "Crop_recommendation_cleaned.csv")
numerical_cols <- c("N", "P", "K", "temperature", "humidity", "ph", "rainfall")

section <- function(title) {
  cat("========================================\n")
  cat(title, "\n")
  cat("========================================\n")
}

# ============================
# 1. Load dataset
# ============================
section("LOADING DATASET")
data <- read.csv(input_file, stringsAsFactors = FALSE)
rows_original <- nrow(data)
cat("Dimensions:", rows_original, "rows x", ncol(data), "columns\n\n")
str(data)
cat("\n")

# ============================
# 2. Exact duplicates
# ============================
section("DUPLICATE ANALYSIS")
duplicate_count <- sum(duplicated(data))
cat("Exact duplicate rows:", duplicate_count,
    sprintf("(%.2f %%)\n", 100 * duplicate_count / nrow(data)))
data <- data[!duplicated(data), ]
cat("Remaining rows:", nrow(data), "\n\n")

# ============================
# 3. Near-duplicates with missing values
# ============================
# A row with a missing value that matches a complete row on every other column
# is a damaged copy of that row: drop it instead of imputing it.
section("NEAR-DUPLICATES WITH MISSING VALUES")
incomplete <- which(!complete.cases(data))
complete_rows <- data[complete.cases(data), ]
is_damaged_copy <- vapply(incomplete, function(i) {
  known <- names(data)[!is.na(data[i, ])]
  same <- Reduce(`&`, lapply(known, function(k) complete_rows[[k]] == data[[k]][i]))
  any(same)
}, logical(1))
cat("Rows with missing values:", length(incomplete), "\n")
cat("Of those, copies of an existing complete row:", sum(is_damaged_copy), "\n")
if (any(is_damaged_copy)) data <- data[-incomplete[is_damaged_copy], ]
cat("Remaining rows:", nrow(data), "\n\n")

# ============================
# 4. Impute genuinely missing values
# ============================
# Per-crop median: crops have very different nutrient needs, so a global
# median would pull values toward the wrong range.
section("MISSING VALUE ANALYSIS")
missing_summary <- data.frame(
  Missing_Count = colSums(is.na(data)),
  Missing_Percentage = round(100 * colSums(is.na(data)) / nrow(data), 2)
)
print(missing_summary)
for (col in numerical_cols) {
  n_missing <- sum(is.na(data[[col]]))
  if (n_missing > 0) {
    crop_median <- ave(data[[col]], data$label,
                       FUN = function(v) median(v, na.rm = TRUE))
    data[[col]][is.na(data[[col]])] <- crop_median[is.na(data[[col]])]
    cat("  - Imputed", n_missing, "value(s) in", col, "with per-crop median\n")
  }
}
cat("Remaining missing values:", sum(is.na(data)), "\n\n")

# ============================
# 5. Summary and save
# ============================
section("PREPROCESSING SUMMARY")
cat("Original rows:", rows_original, "\n")
cat("Final rows:   ", nrow(data), "\n")
cat("Rows removed: ", rows_original - nrow(data), "\n\n")
cat("Rows per crop:\n")
print(table(data$label))
cat("\n")
print(summary(data))

write.csv(data, output_file, row.names = FALSE)
cat("\nCleaned dataset saved as:", output_file, "\n")
