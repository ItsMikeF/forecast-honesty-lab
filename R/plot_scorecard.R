# plot_scorecard.R: draws assets/scorecard.png from data/models.csv
#
# One tile per model, grouped by what happened when its forecasts were priced
# against sportsbook markets. Run from the repo root:
#
#   Rscript R/plot_scorecard.R
#
# Chart rules this follows:
#   * The background is declared on the plot AND the device, so the PNG is
#     never transparent and reads the same in GitHub's light and dark themes.
#   * Near-white text on a dark surface.
#   * Colour is never the only signal: every tier is also a labelled row.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(ggplot2)
  library(ragg)
})

models <- read_csv("data/models.csv", show_col_types = FALSE)

# ---- palette ----------------------------------------------------------------
BG    <- "#12151a"   # surface
INK   <- "#f2f4f7"   # primary text
INK2  <- "#c3cbd6"   # secondary text
MUTED <- "#8d97a4"   # captions
LINE  <- "#39414c"   # hairlines

FONT_TEXT  <- "Segoe UI"
FONT_TITLE <- "Bahnschrift"

# Tier order is the reading order: the bar a model has to clear comes first.
tiers <- tibble(
  tier   = c("proven", "thin edge", "no edge", "untested", "legacy"),
  header = c("Proven", "Thin edge", "No edge", "Never market-tested", "Legacy"),
  blurb  = c("a significant win over closing prices, across seasons",
             "ahead of the market by a small or insignificant margin",
             "tested against market prices and lost",
             "no market, no price history, or results pending",
             "retired"),
  fill   = c("#5fd08a", "#e8b93b", "#e07a5f", "#1d232c", BG),
  ink    = c(BG,        BG,        BG,        INK2,      MUTED),
  edge   = c("#5fd08a", "#e8b93b", "#e07a5f", LINE,      LINE),
  accent = c("#5fd08a", "#e8b93b", "#e07a5f", INK2,      MUTED)
)

# Sanity check: every model must land in a known tier, or it silently vanishes.
stopifnot(all(models$tier %in% tiers$tier))

# ---- layout: rows of PER_ROW tiles, one block per tier ----------------------
PER_ROW <- 5
TILE_X0 <- 3.35   # x of the first tile column; tier headers sit to its left
GAP     <- 0.6    # vertical gap between tier blocks

sport_order <- c("College football", "Baseball", "NFL", "Hockey",
                 "Soccer (Big 5 leagues)", "Soccer (EPL)", "Tennis (ATP)", "MMA")

y_top <- 0
tile_list <- list()
head_list <- list()
for (k in seq_len(nrow(tiers))) {
  tr <- tiers[k, ]
  d <- models %>%
    filter(tier == tr$tier) %>%
    mutate(sport_rank = match(sport, sport_order)) %>%
    arrange(sport_rank, tolower(short_label))
  n_rows <- max(1, ceiling(nrow(d) / PER_ROW))   # an empty tier still gets a row

  if (nrow(d) > 0) {
    tile_list[[k]] <- d %>%
      mutate(i     = row_number() - 1,
             x     = TILE_X0 + i %% PER_ROW,
             y     = y_top - i %/% PER_ROW,
             fill  = tr$fill,
             ink   = tr$ink,
             edge  = tr$edge,
             label = str_wrap(short_label, 12))
  }
  head_list[[k]] <- tr %>% mutate(n = nrow(d), y = y_top, n_rows = n_rows)
  y_top <- y_top - n_rows - GAP
}
tiles <- bind_rows(tile_list)
heads <- bind_rows(head_list)

empty_tiers <- heads %>% filter(n == 0)
y_min <- min(c(tiles$y, heads$y - heads$n_rows + 1)) - 0.55

# ---- counts for the headline (computed, never typed) ------------------------
n_all    <- nrow(models)
n_tested <- sum(models$tier %in% c("proven", "thin edge", "no edge"))
n_lost   <- sum(models$tier == "no edge")
n_thin   <- sum(models$tier == "thin edge")
n_proven <- sum(models$tier == "proven")

title_txt <- sprintf("%d forecasting models, %d tested against market prices",
                     n_all, n_tested)
subtitle_txt <- sprintf(paste0(
  "%d lost to the market, %d came out slightly ahead, and %s proven an edge yet. ",
  "Each tile is one model. Status as of November 2026."),
  n_lost, n_thin, if (n_proven == 0) "none has" else paste(n_proven, "have"))

caption_txt <- paste0(
  "Market test: the model's out-of-sample forecasts priced against real sportsbook prices ",
  "that were available at the time.\n",
  "Tiers come from each model's own status note; a tier moves on a market test only, ",
  "never on an accuracy gain.  Data and code: github.com/ItsMikeF/forecast-honesty-lab")

# ---- plot -------------------------------------------------------------------
p <- ggplot() +
  # tier headers: big count in the tier's accent colour, name and meaning beside it
  geom_text(data = heads, aes(x = 0.25, y = y, label = n, colour = accent),
            family = FONT_TITLE, size = 11, hjust = 0, vjust = 0.5) +
  geom_text(data = heads, aes(x = 0.98, y = y + 0.13, label = header),
            family = FONT_TEXT, fontface = "bold", size = 4.6, hjust = 0,
            colour = INK) +
  geom_text(data = heads, aes(x = 0.98, y = y - 0.2, label = str_wrap(blurb, 30)),
            family = FONT_TEXT, size = 3.05, hjust = 0, vjust = 1,
            lineheight = 0.95, colour = MUTED) +
  # the tiles
  geom_tile(data = tiles, aes(x = x, y = y, fill = fill, colour = edge),
            width = 0.94, height = 0.8, linewidth = 0.5) +
  geom_text(data = tiles, aes(x = x, y = y, label = label, colour = ink),
            family = FONT_TEXT, size = 3.55, lineheight = 0.92) +
  # an empty tier is drawn as an empty, dashed row: the absence is the point
  geom_tile(data = empty_tiers,
            aes(x = TILE_X0 + (PER_ROW - 1) / 2, y = y, colour = edge),
            width = PER_ROW - 0.06, height = 0.8, fill = NA,
            linewidth = 0.5, linetype = "22") +
  geom_text(data = empty_tiers,
            aes(x = TILE_X0 + (PER_ROW - 1) / 2, y = y, label = "None yet"),
            family = FONT_TEXT, size = 3.8, colour = MUTED) +
  scale_fill_identity() +
  scale_colour_identity() +
  coord_cartesian(xlim = c(0.1, TILE_X0 + PER_ROW - 0.45),
                  ylim = c(y_min, 0.55), expand = FALSE, clip = "off") +
  labs(title = title_txt, subtitle = subtitle_txt, caption = caption_txt) +
  theme_void(base_family = FONT_TEXT) +
  theme(
    plot.background  = element_rect(fill = BG, colour = NA),
    panel.background = element_rect(fill = BG, colour = NA),
    plot.title    = element_text(family = FONT_TITLE, size = 21, colour = INK,
                                 margin = margin(b = 6)),
    plot.subtitle = element_text(size = 11.5, colour = INK2, margin = margin(b = 18)),
    plot.caption  = element_text(size = 8.6, colour = MUTED, hjust = 0,
                                 lineheight = 1.25, margin = margin(t = 16)),
    plot.caption.position = "plot",
    plot.title.position   = "plot",
    plot.margin = margin(26, 30, 18, 30)
  )

dir.create("assets", showWarnings = FALSE)
ragg::agg_png("assets/scorecard.png", width = 1600, height = 1240, res = 150,
              background = BG)
print(p)
invisible(dev.off())
message("wrote assets/scorecard.png  (", n_all, " models, ", n_tested, " tested)")
