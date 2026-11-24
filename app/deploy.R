# Deploy the app to shinyapps.io (free tier).
#
# One-time setup:
#   1. Create a free account at https://www.shinyapps.io
#   2. In the dashboard: Account -> Tokens -> Show -> copy the setAccountInfo() line
#   3. Run that line once in R (it stores the credentials locally; never commit them)
#
# Then, from the repository root:  Rscript app/deploy.R

if (nrow(rsconnect::accounts()) == 0) {
  stop("No shinyapps.io account configured. Follow the setup steps at the top of app/deploy.R.")
}

rsconnect::deployApp(
  appDir = "app",
  appFiles = c("app.R", "data/model.rds", "data/crop_ranges.csv",
               "data/district_crops.csv", "data/district_all_crops.csv"),
  appName = "crop-recommender",
  forceUpdate = TRUE
)
