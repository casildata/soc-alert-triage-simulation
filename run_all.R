# Reproduce every table and figure from the repository root:
#   Rscript run_all.R
# Packages: listed in r-packages.txt; the run stops with install instructions if any are missing.
source("R/check_packages.R")
source("R/params.R")
source("R/validate.R")
source("R/report.R")
source("R/metrics.R")
invisible(lapply(SCENARIOS, validate_params))

dir.create("outputs", showWarnings = FALSE)
dir.create("docs/figures", showWarnings = FALSE, recursive = TRUE)

message("==> scripts/00_queueing_check.R")
source("scripts/00_queueing_check.R")

source("R/model.R")
for (s in c("scripts/01_simulate.R", "scripts/02_analyze.R", "scripts/03_stress_test.R",
            "scripts/04_daily_cycle.R")) {
  message("==> ", s)
  source(s, echo = FALSE)
}
report_write("docs/results.md")
message("Results written to docs/results.md")
