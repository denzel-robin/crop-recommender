app_data <- file.path(root, "app", "data")

test_that("app model recommends the right crop for known examples", {
  m <- readRDS(file.path(app_data, "model.rds"))
  crops <- read.csv(file.path(root, "dataset", "Crop_recommendation_cleaned.csv"))
  set.seed(1)
  sample_rows <- crops[sample(nrow(crops), 50), ]
  pred <- ranger:::predict.ranger(m$model, sample_rows[m$features])$predictions
  top <- colnames(pred)[max.col(pred)]
  expect_gte(mean(top == sample_rows$label), 0.95)
})

test_that("out-of-distribution threshold flags an impossible reading", {
  m <- readRDS(file.path(app_data, "model.rds"))
  z <- (c(N = 60, P = 45, K = 400, temperature = 25, humidity = 75, ph = 6.5, rainfall = 100) -
          m$centre) / m$spread
  nearest <- min(sqrt(colSums((t(m$train_scaled) - z)^2)))
  expect_gt(nearest, m$nn_threshold)
})

test_that("district data covers the modelled crops and has sane values", {
  dc <- read.csv(file.path(app_data, "district_crops.csv"))
  expect_gte(length(unique(dc$label)), 21)
  expect_true(all(dc$mean_area_ha > 0))
  expect_true(all(dc$yield_vs_state > 0, na.rm = TRUE))
  expect_true("Pune" %in% dc$district[dc$state == "Maharashtra"])
})
