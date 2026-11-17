# render_readme.R: rebuilds the scorecard tables in README.md from data/models.csv
#
# Everything between the <!-- scorecard:start --> and <!-- scorecard:end -->
# markers is regenerated; the rest of the README is left alone. Run from the
# repo root:
#
#   Rscript R/render_readme.R

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
})

models <- read_csv("data/models.csv", show_col_types = FALSE)

sport_order <- c("College football", "Baseball", "NFL", "Hockey",
                 "Soccer (Big 5 leagues)", "Soccer (EPL)", "Tennis (ATP)", "MMA")

by_sport <- function(d) {
  d %>% mutate(r = match(sport, sport_order)) %>% arrange(r, tolower(model))
}

# A pipe inside a cell would split the markdown table; fail loudly instead.
stopifnot(!any(str_detect(unlist(models), fixed("|")), na.rm = TRUE))

md_table <- function(d, last_header) {
  head <- paste0("| Model | Forecasts | Tested on | Result | ", last_header, " |\n",
                 "|---|---|---|---|---|")
  rows <- sprintf("| **%s** | %s | %s | %s | %s |",
                  d$model, d$forecasts, d$sample, d$result, d$lesson)
  paste(c(head, rows), collapse = "\n")
}

thin     <- models %>% filter(tier == "thin edge") %>% by_sport()
lost     <- models %>% filter(tier == "no edge")   %>% by_sport()
untested <- models %>% filter(tier %in% c("untested", "legacy")) %>% by_sport()

# The README must never claim a proven model the data doesn't have, or hide one it does.
stopifnot(sum(models$tier == "proven") == 0)

block <- paste0(
  "### Thin edge (", nrow(thin), "): ahead of the market, not yet proven\n\n",
  md_table(thin, "Caveat"), "\n\n",
  "### No edge (", nrow(lost), "): tested against market prices and lost\n\n",
  md_table(lost, "What it taught me"), "\n\n",
  "<details>\n<summary><b>Never market-tested (", sum(untested$tier == "untested"),
  ") and retired (", sum(untested$tier == "legacy"), ")</b>: ",
  "no market exists, no price history exists, or results are pending</summary>\n\n",
  "| Model | Forecasts | Status |\n|---|---|---|\n",
  paste(sprintf("| %s | %s | %s |", untested$model, untested$forecasts, untested$result),
        collapse = "\n"),
  "\n\n</details>"
)

readme <- read_file("README.md")
loc <- str_locate(readme, regex("<!-- scorecard:start -->.*<!-- scorecard:end -->",
                                dotall = TRUE))
stopifnot(!is.na(loc[1, "start"]))

# Splice by position rather than regex replacement, so nothing in the table text
# (a "$" or a backslash) can be read as a replacement token.
out <- paste0(str_sub(readme, 1, loc[1, "start"] - 1),
              "<!-- scorecard:start -->\n", block, "\n<!-- scorecard:end -->",
              str_sub(readme, loc[1, "end"] + 1))
write_file(out, "README.md")
message("README tables rebuilt: ", nrow(thin), " thin edge, ", nrow(lost),
        " no edge, ", nrow(untested), " untested or legacy")
