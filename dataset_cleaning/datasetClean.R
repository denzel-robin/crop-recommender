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
source(file.path("R", "cleaning.R"))

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
# 2-4. Clean (functions in R/cleaning.R)
# ============================
section("DUPLICATE ANALYSIS")
duplicate_count <- sum(duplicated(data))
cat("Exact duplicate rows:", duplicate_count,
    sprintf("(%.2f %%)\n", 100 * duplicate_count / nrow(data)))
data <- remove_exact_duplicates(data)
cat("Remaining rows:", nrow(data), "\n\n")

section("NEAR-DUPLICATES WITH MISSING VALUES")
n_incomplete <- sum(!complete.cases(data))
rows_before_copies <- nrow(data)
data <- remove_damaged_copies(data)
cat("Rows with missing values:", n_incomplete, "\n")
cat("Of those, copies of an existing complete row:", rows_before_copies - nrow(data), "\n")
cat("Remaining rows:", nrow(data), "\n\n")

section("MISSING VALUE ANALYSIS")
print(data.frame(Missing_Count = colSums(is.na(data))))
data <- impute_crop_median(data)
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
