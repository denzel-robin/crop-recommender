# Run all tests from the repository root:  Rscript tests/testthat.R
library(testthat)
root <- normalizePath(".")
test_dir(file.path(root, "tests", "testthat"), env = new.env(), stop_on_failure = TRUE,
         reporter = "summary")
