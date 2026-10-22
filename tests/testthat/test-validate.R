rejects <- function(...) expect_error(validate_params(modifyList(baseline, list(...))))

test_that("every scenario in R/params.R passes validation", {
  for (sc in SCENARIOS) expect_true(validate_params(sc))
  for (x in DAY$staffing) {
    expect_true(validate_params(modifyList(baseline, list(hourly_profile = DAY$hourly_profile,
                                                          tier1_analysts = x, tier2_analysts = x))))
  }
})

test_that("invalid parameters are rejected", {
  rejects(severity_mix = c(high = 0.2, medium = 0.3, low = 0.6))
  rejects(triage_time = list(high = c(10, 5, 25)))
  rejects(true_positive_rate = c(high = 1.5, medium = 0.2, low = 0.05))
  rejects(tier2_analysts = 0)
  rejects(tier1_analysts = c(2, 3))                      # not one per shift
  rejects(hourly_profile = rep(1, 23))
  rejects(fp_suppression = 0.6)                          # more than high's false-positive share
  rejects(flood = list(rate = 20, minutes = 60, plant_at = 90, start = 0))
})
