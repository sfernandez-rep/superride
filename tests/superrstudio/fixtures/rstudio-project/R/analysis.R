# Synthetic fixture for the SuperR project-compatibility check. The data are
# invented (twelve rows of made-up catches); no research data is included.
# Paths are relative to the project directory, as in a typical RStudio
# project. Running this script writes into output/ of the project copy.

catches <- read.csv(file.path("data", "catches.csv"), stringsAsFactors = FALSE)
catches$date <- as.Date(catches$date)

stations <- readRDS(file.path("data", "stations.rds"))
load(file.path("data", "survey.RData"))   # creates `survey_info`

summary_by_species <- aggregate(length_cm ~ species, data = catches, FUN = mean)
merged <- merge(catches, stations, by = "station")

dir.create("output", showWarnings = FALSE)
write.csv(summary_by_species, file.path("output", "summary.csv"), row.names = FALSE)
saveRDS(merged, file.path("output", "merged.rds"))

if (requireNamespace("ggplot2", quietly = TRUE)) {
  plot <- ggplot2::ggplot(merged, ggplot2::aes(x = length_cm, y = weight_g, colour = species)) +
    ggplot2::geom_point() +
    ggplot2::labs(title = survey_info$title, x = "Length (cm)", y = "Weight (g)")
  ggplot2::ggsave(file.path("output", "length-weight.png"), plot, width = 6, height = 4, dpi = 96)
}

cat("rows:", nrow(merged), "species:", nrow(summary_by_species), "\n")
