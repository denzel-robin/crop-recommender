# Crop recommendation app
#
# Combines a soil and climate model with real district crop-production
# statistics. Build the data first:  Rscript app/prepare_data.R
# Run locally from the repository root:  Rscript -e 'shiny::runApp("app")'

library(shiny)
library(bslib)
library(ranger)

data_dir <- "data"
m <- readRDS(file.path(data_dir, "model.rds"))
crop_ranges <- read.csv(file.path(data_dir, "crop_ranges.csv"))
district_crops <- read.csv(file.path(data_dir, "district_crops.csv"))
district_all <- read.csv(file.path(data_dir, "district_all_crops.csv"))

states <- sort(unique(district_all$state))
feature_info <- data.frame(
  id = m$features,
  label = c("Nitrogen (N)", "Phosphorus (P)", "Potassium (K)", "Temperature (°C)",
            "Humidity (%)", "Soil pH", "Rainfall (mm)"),
  step = c(1, 1, 1, 0.1, 0.1, 0.1, 1),
  stringsAsFactors = FALSE
)
defaults <- c(N = 60, P = 45, K = 40, temperature = 25, humidity = 75, ph = 6.5, rainfall = 100)
pretty_crop <- function(x) tools::toTitleCase(gsub("beans$", " beans", gsub("peas$", " peas", x)))
fmt_num <- function(x, digits = 0) ifelse(is.na(x), "–", formatC(x, format = "f", digits = digits, big.mark = ","))

feature_input <- function(i) {
  f <- feature_info[i, ]
  numericInput(f$id, f$label, value = defaults[[f$id]],
               min = floor(m$feature_min[[f$id]] * 0.5), max = ceiling(m$feature_max[[f$id]] * 1.5),
               step = f$step)
}

ui <- page_sidebar(
  title = "Crop Recommender",
  theme = bs_theme(version = 5, primary = "#2a6f97"),
  sidebar = sidebar(
    width = 300,
    h6("Soil test"),
    lapply(1:3, feature_input),
    feature_input(6),
    h6("Climate"),
    lapply(c(4, 5, 7), feature_input),
    h6("Location"),
    selectInput("state", "State", choices = states, selected = "Maharashtra"),
    selectInput("district", "District", choices = NULL),
    checkboxInput("local_only", "Only crops grown in this district", value = FALSE)
  ),
  navset_card_underline(
    nav_panel(
      "Recommendations",
      uiOutput("ood_warning"),
      uiOutput("recommendations"),
      p(class = "text-muted small mt-2",
        "Match = model probability from soil and climate. District columns come from government crop statistics, 2002–2014.",
        "Yield vs state compares the district's median yield with the state median for that crop.")
    ),
    nav_panel(
      "Why this crop?",
      selectInput("explain_crop", "Crop", choices = NULL),
      uiOutput("explanation")
    ),
    nav_panel(
      "What grows here",
      uiOutput("local_crops")
    ),
    nav_panel(
      "About",
      div(
        class = "p-2", style = "max-width: 760px;",
        h5("What this app does"),
        p("It ranks 22 crops by how well your soil and climate readings match each crop's typical conditions,",
          "then checks each crop against what farmers in your district actually grow and how well it yields there."),
        h5("Limits you should know"),
        tags$ul(
          tags$li("The soil and climate model is trained on the public Kaggle Crop Recommendation dataset. This project showed that its N, P and K values are random numbers around one fertilizer dose per crop, not field measurements. Treat the match score as a rough guide."),
          tags$li("On real Soil Health Card data from Pune, soil readings added little beyond knowing the village. That is why the district evidence sits next to every recommendation."),
          tags$li("Readings that look unlike anything in the training data trigger a warning, and the scores are then less reliable."),
          tags$li("This is a portfolio project, not agronomic advice. Ask your local agricultural office before choosing a crop.")
        ),
        p(a("Source code and full analysis", href = "https://github.com/denzel-robin/crop-recommender",
            target = "_blank"))
      )
    )
  )
)

server <- function(input, output, session) {
  observeEvent(input$state, {
    districts <- sort(unique(district_all$district[district_all$state == input$state]))
    default <- if ("Pune" %in% districts) "Pune" else districts[1]
    updateSelectInput(session, "district", choices = districts, selected = default)
  })

  readings <- reactive({
    vals <- sapply(m$features, function(f) input[[f]])
    req(all(!vapply(vals, is.null, logical(1))), all(!is.na(unlist(vals))))
    as.data.frame(as.list(unlist(vals)))
  })

  ood <- reactive({
    x <- readings()
    z <- (unlist(x[m$features]) - m$centre) / m$spread
    nearest <- min(sqrt(colSums((t(m$train_scaled) - z)^2)))
    outside <- m$features[unlist(x[m$features]) < m$feature_min | unlist(x[m$features]) > m$feature_max]
    list(far = nearest > m$nn_threshold, nearest = nearest, outside = outside)
  })

  scored <- reactive({
    req(input$district, input$district %in% district_all$district[district_all$state == input$state])
    probs <- predict(m$model, readings())$predictions[1, ]
    res <- data.frame(label = names(probs), prob = as.numeric(probs), stringsAsFactors = FALSE)
    local <- district_crops[district_crops$state == input$state & district_crops$district == input$district, ]
    res <- merge(res, local[, c("label", "years", "mean_area_ha", "yield_vs_state", "seasons")],
                 by = "label", all.x = TRUE)
    res$grown <- !is.na(res$mean_area_ha)
    res[order(-res$prob), ]
  })

  shown <- reactive({
    res <- scored()
    if (isTRUE(input$local_only)) res <- res[res$grown, ]
    head(res, 5)
  })

  observe({
    choices <- setNames(shown()$label, pretty_crop(shown()$label))
    updateSelectInput(session, "explain_crop", choices = choices,
                      selected = if (length(choices)) choices[[1]] else NULL)
  })

  output$ood_warning <- renderUI({
    o <- ood()
    if (!o$far && length(o$outside) == 0) return(NULL)
    msg <- if (length(o$outside)) {
      paste0("Outside the range seen in training: ",
             paste(feature_info$label[match(o$outside, feature_info$id)], collapse = ", "), ". ")
    } else ""
    div(class = "alert alert-warning",
        strong("Unusual readings. "), msg,
        "This combination is unlike any training example, so the match scores below are less reliable.",
        "Double-check the values or rely more on the district evidence.")
  })

  output$recommendations <- renderUI({
    res <- shown()
    if (nrow(res) == 0) {
      return(div(class = "alert alert-info",
                 "None of the 22 modelled crops is recorded in this district. See \"What grows here\"."))
    }
    rows <- lapply(seq_len(nrow(res)), function(i) {
      r <- res[i, ]
      pct <- round(100 * r$prob)
      local <- if (r$grown) {
        tagList(
          tags$td(span(class = "badge text-bg-success", "Grown here")),
          tags$td(fmt_num(r$mean_area_ha)),
          tags$td(if (is.na(r$yield_vs_state)) "–" else sprintf("%.2f×", r$yield_vs_state)),
          tags$td(r$seasons)
        )
      } else {
        tagList(tags$td(span(class = "badge text-bg-secondary", "Not recorded")),
                tags$td("–"), tags$td("–"), tags$td("–"))
      }
      tags$tr(
        tags$td(strong(pretty_crop(r$label))),
        tags$td(style = "min-width: 160px;",
                div(class = "d-flex align-items-center gap-2",
                    div(class = "progress flex-grow-1", style = "height: 10px;",
                        div(class = "progress-bar", style = sprintf("width: %d%%;", pct))),
                    span(sprintf("%d%%", pct)))),
        local
      )
    })
    tags$div(class = "table-responsive",
      tags$table(class = "table align-middle",
        tags$thead(tags$tr(tags$th("Crop"), tags$th("Match"), tags$th("District"),
                           tags$th("Area (ha/yr)"), tags$th("Yield vs state"), tags$th("Seasons"))),
        tags$tbody(rows)))
  })

  output$explanation <- renderUI({
    req(input$explain_crop)
    rng <- crop_ranges[crop_ranges$label == input$explain_crop, ]
    x <- readings()
    rows <- lapply(seq_len(nrow(feature_info)), function(i) {
      f <- feature_info$id[i]
      lo <- rng[[paste0(f, "_lo")]]; hi <- rng[[paste0(f, "_hi")]]; v <- x[[f]]
      status <- if (v < lo) "Below typical" else if (v > hi) "Above typical" else "Within typical"
      cls <- if (status == "Within typical") "text-bg-success" else "text-bg-warning"
      digits <- if (f %in% c("N", "P", "K")) 0 else 1
      tags$tr(tags$td(feature_info$label[i]), tags$td(fmt_num(v, digits)),
              tags$td(paste(fmt_num(lo, digits), "to", fmt_num(hi, digits))),
              tags$td(span(class = paste("badge", cls), status)))
    })
    n_ok <- sum(vapply(rows, function(r) grepl("Within", as.character(r)), logical(1)))
    tagList(
      p(sprintf("%d of 7 readings fall within the typical range for %s (5th–95th percentile of the training data).",
                n_ok, pretty_crop(input$explain_crop))),
      tags$div(class = "table-responsive",
        tags$table(class = "table align-middle",
          tags$thead(tags$tr(tags$th("Reading"), tags$th("Yours"), tags$th("Typical"), tags$th(""))),
          tags$tbody(rows)))
    )
  })

  output$local_crops <- renderUI({
    req(input$district)
    local <- district_all[district_all$state == input$state & district_all$district == input$district, ]
    local <- head(local[order(-local$mean_area_ha), ], 15)
    if (nrow(local) == 0) return(p("No production records for this district."))
    rows <- lapply(seq_len(nrow(local)), function(i) {
      r <- local[i, ]
      tags$tr(tags$td(r$crop), tags$td(fmt_num(r$mean_area_ha)),
              tags$td(sprintf("%.1f%%", 100 * r$area_share)), tags$td(r$seasons))
    })
    tagList(
      p(sprintf("Largest crops by area in %s, %s (average per year, 2002–2014).", input$district, input$state)),
      tags$div(class = "table-responsive",
        tags$table(class = "table align-middle",
          tags$thead(tags$tr(tags$th("Crop"), tags$th("Area (ha/yr)"), tags$th("Share of area"), tags$th("Seasons"))),
          tags$tbody(rows))))
  })
}

shinyApp(ui, server)
