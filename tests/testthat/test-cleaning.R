source(file.path(root, "R", "cleaning.R"))

toy <- data.frame(
  N = c(10, 10, 20, 30, 30, 40, 50),
  P = c(5, 5, 6, NA, 7, NA, 11),
  K = c(1, 1, 2, 3, 3, 4, 5),
  temperature = 20, humidity = 50, ph = 6.5, rainfall = 100,
  label = c("rice", "rice", "rice", "maize", "maize", "maize", "maize")
)

test_that("exact duplicates are removed", {
  out <- remove_exact_duplicates(toy)
  expect_equal(nrow(out), 6)
  expect_false(any(duplicated(out)))
})

test_that("a row with a blanked value that copies a complete row is dropped", {
  out <- remove_damaged_copies(remove_exact_duplicates(toy))
  # row 4 (N = 30, P = NA) copies row 5 (N = 30, P = 7); row 6 is a genuine gap
  expect_equal(nrow(out), 5)
  expect_false(any(out$N == 30 & is.na(out$P)))
  expect_true(any(out$N == 40 & is.na(out$P)))
})

test_that("genuine gaps are filled with the same crop's median", {
  out <- impute_crop_median(remove_damaged_copies(remove_exact_duplicates(toy)))
  expect_equal(sum(is.na(out)), 0)
  expect_equal(out$P[out$N == 40], 9)  # median of the other maize rows (7, 11)
})

test_that("cleaning order matters: imputing first would keep the damaged copy", {
  wrong_order <- remove_exact_duplicates(impute_crop_median(toy))
  right_order <- clean_crop_data(toy)
  expect_gt(nrow(wrong_order), nrow(right_order))
})

test_that("the cleaned project dataset is balanced and complete", {
  raw <- read.csv(file.path(root, "dataset", "Crop_recommendation.csv"))
  cleaned <- clean_crop_data(raw)
  expect_equal(nrow(cleaned), 2200)
  expect_equal(sum(is.na(cleaned)), 0)
  expect_true(all(table(cleaned$label) == 100))
  expect_equal(length(unique(cleaned$label)), 22)
})
