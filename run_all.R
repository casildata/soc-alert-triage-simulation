# Reproduce every table and figure from the repository root:
#   Rscript run_all.R
# Packages: listed in r-packages.txt; missing ones are installed on first run.
source("R/check_packages.R")
source("R/params.R")
source("R/report.R")
source("R/metrics.R")

dir.create("outputs", showWarnings = FALSE)
dir.create("docs/figures", showWarnings = FALSE, recursive = TRUE)

message("==> scripts/00_queueing_check.R")
source("scripts/00_queueing_check.R")

if (!requireNamespace("simmer", quietly = TRUE)) {
  report_add("\n> Simulation not run: package `simmer` is not installed. ",
             "Run `install.packages(\"simmer\")`, then `Rscript run_all.R`.\n")
  report_write("docs/results.md")
  stop("simmer is not installed; only the analytic check was written to docs/results.md")
}

source("R/model.R")
for (s in c("scripts/01_simulate.R", "scripts/02_analyze.R", "scripts/03_stress_test.R")) {
  message("==> ", s)
  source(s, echo = FALSE)
}
report_write("docs/results.md")
message("Results written to docs/results.md")
