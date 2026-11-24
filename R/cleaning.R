# Cleaning functions for the crop recommendation data.
# Used by dataset_cleaning/datasetClean.R and tested in tests/testthat/.

numerical_cols <- c("N", "P", "K", "temperature", "humidity", "ph", "rainfall")

# Drop rows that exactly repeat an earlier row.
remove_exact_duplicates <- function(data) {
  data[!duplicated(data), , drop = FALSE]
}

# Drop rows with missing values that match a complete row on every column they
# do have: they are damaged copies of that row, not new samples. Must run
# BEFORE imputation, otherwise the filled-in copies survive de-duplication.
remove_damaged_copies <- function(data) {
  incomplete <- which(!complete.cases(data))
  if (length(incomplete) == 0) return(data)
  complete_rows <- data[complete.cases(data), , drop = FALSE]
  is_copy <- vapply(incomplete, function(i) {
    known <- names(data)[!is.na(data[i, ])]
    same <- Reduce(`&`, lapply(known, function(k) complete_rows[[k]] == data[[k]][i]),
                   init = rep(TRUE, nrow(complete_rows)))
    any(same)
  }, logical(1))
  if (any(is_copy)) data <- data[-incomplete[is_copy], , drop = FALSE]
  data
}

# Fill remaining gaps in numeric columns with the median of the same crop.
impute_crop_median <- function(data, cols = intersect(numerical_cols, names(data))) {
  for (col in cols) {
    missing <- is.na(data[[col]])
    if (any(missing)) {
      crop_median <- ave(data[[col]], data$label, FUN = function(v) median(v, na.rm = TRUE))
      data[[col]][missing] <- crop_median[missing]
    }
  }
  data
}

# Full pipeline, in the order that matters.
clean_crop_data <- function(data) {
  data |>
    remove_exact_duplicates() |>
    remove_damaged_copies() |>
    impute_crop_median()
}
