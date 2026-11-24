# Builds everything the Shiny app needs into app/data/, so the app itself only
# depends on shiny, bslib and ranger.
#
# Run from the repository root:  Rscript app/prepare_data.R

suppressPackageStartupMessages({
  library(dplyr)
})

out <- file.path("app", "data")
dir.create(out, showWarnings = FALSE, recursive = TRUE)
features <- c("N", "P", "K", "temperature", "humidity", "ph", "rainfall")

# ----------------------------------------------------------------------------
# 1. Soil and climate model (same hyperparameters as the tuned benchmark RF)
# ----------------------------------------------------------------------------
crops <- read.csv(file.path("dataset", "Crop_recommendation_cleaned.csv")) |>
  mutate(label = factor(label))

best <- readRDS(file.path("modelling", "results", "best_model.rds"))
rf <- workflows::extract_fit_engine(best)
model <- ranger::ranger(
  x = crops[features], y = crops$label, probability = TRUE,
  num.trees = 500, mtry = rf$mtry, min.node.size = rf$min.node.size, seed = 42
)

# Out-of-distribution check: distance to the nearest training row on
# standardised features, against the 99th percentile of leave-one-out distances
centre <- sapply(crops[features], mean)
spread <- sapply(crops[features], sd)
train_scaled <- scale(as.matrix(crops[features]), centre, spread)
d <- as.matrix(dist(train_scaled))
diag(d) <- Inf
nn_threshold <- unname(quantile(apply(d, 1, min), 0.99))

saveRDS(list(model = model, features = features, centre = centre, spread = spread,
             train_scaled = train_scaled, nn_threshold = nn_threshold,
             feature_min = sapply(crops[features], min),
             feature_max = sapply(crops[features], max)),
        file.path(out, "model.rds"))

# Typical range (5th-95th percentile) of each feature for each crop
crop_ranges <- crops |>
  group_by(label) |>
  summarise(across(all_of(features),
                   list(lo = \(x) quantile(x, 0.05), hi = \(x) quantile(x, 0.95))),
            .groups = "drop")
write.csv(crop_ranges, file.path(out, "crop_ranges.csv"), row.names = FALSE)

# ----------------------------------------------------------------------------
# 2. District evidence from real crop production statistics
# ----------------------------------------------------------------------------
# Kaggle crop label -> crop name(s) in the production data. Muskmelon has no
# matching series.
crop_map <- tibble::tribble(
  ~label,        ~production_crop,
  "rice",        "Rice",
  "maize",       "Maize",
  "chickpea",    "Gram",
  "kidneybeans", "Rajmash Kholar",
  "pigeonpeas",  "Arhar/Tur",
  "mothbeans",   "Moth",
  "mungbean",    "Moong(Green Gram)",
  "blackgram",   "Urad",
  "blackgram",   "Blackgram",
  "lentil",      "Masoor",
  "lentil",      "Lentil",
  "pomegranate", "Pome Granet",
  "banana",      "Banana",
  "mango",       "Mango",
  "grapes",      "Grapes",
  "watermelon",  "Water Melon",
  "apple",       "Apple",
  "orange",      "Orange",
  "papaya",      "Papaya",
  "coconut",     "Coconut",
  "cotton",      "Cotton(lint)",
  "jute",        "Jute",
  "coffee",      "Coffee"
)

production <- read.csv(file.path("dataset", "external", "india_crop_production.csv.gz")) |>
  mutate(across(c(State_Name, District_Name, Season, Crop), trimws),
         District_Name = tools::toTitleCase(tolower(District_Name)),
         Production = suppressWarnings(as.numeric(Production))) |>
  filter(Area > 0)

# 2002-2014: some fruit series (apple, coffee, watermelon) only exist for 2002-2003
recent_years <- 2002:2014
matched <- production |>
  inner_join(crop_map, by = c("Crop" = "production_crop"), relationship = "many-to-many") |>
  filter(Crop_Year %in% recent_years)

# Area and yield per district and crop, averaged over the recent years
district_crops <- matched |>
  group_by(state = State_Name, district = District_Name, label, Crop_Year) |>
  summarise(area = sum(Area), production = sum(Production, na.rm = TRUE),
            seasons = paste(sort(unique(Season)), collapse = ", "), .groups = "drop") |>
  group_by(state, district, label) |>
  summarise(years = n(),
            mean_area_ha = mean(area),
            yield = median(ifelse(production > 0, production / area, NA), na.rm = TRUE),
            seasons = paste(sort(unique(unlist(strsplit(seasons, ", ")))), collapse = ", "),
            .groups = "drop")

state_yield <- district_crops |>
  group_by(state, label) |>
  summarise(state_median_yield = median(yield, na.rm = TRUE), .groups = "drop")

district_crops <- district_crops |>
  left_join(state_yield, by = c("state", "label")) |>
  mutate(yield_vs_state = yield / state_median_yield) |>
  mutate(across(c(mean_area_ha, yield, state_median_yield, yield_vs_state), \(x) round(x, 2)))
write.csv(district_crops, file.path(out, "district_crops.csv"), row.names = FALSE)

# All crops (not only the 22 modelled) grown in each district, for "What grows here"
district_all <- production |>
  filter(Crop_Year %in% recent_years,
         !grepl("total|other|Total", Crop)) |>
  group_by(state = State_Name, district = District_Name, crop = Crop) |>
  summarise(mean_area_ha = round(sum(Area) / n_distinct(Crop_Year)),
            seasons = paste(sort(unique(Season)), collapse = ", "), .groups = "drop") |>
  group_by(state, district) |>
  mutate(area_share = round(mean_area_ha / sum(mean_area_ha), 4)) |>
  ungroup() |>
  arrange(state, district, desc(mean_area_ha))
write.csv(district_all, file.path(out, "district_all_crops.csv"), row.names = FALSE)

cat("Model OOB error:", round(model$prediction.error, 4), "\n")
cat("Out-of-distribution distance threshold:", round(nn_threshold, 3), "\n")
cat("District-crop rows (modelled crops):", nrow(district_crops),
    "| districts:", n_distinct(paste(district_crops$state, district_crops$district)), "\n")
cat("District-crop rows (all crops):", nrow(district_all), "\n")
cat("Modelled crops with district data:", n_distinct(district_crops$label), "of", nlevels(crops$label), "\n")
