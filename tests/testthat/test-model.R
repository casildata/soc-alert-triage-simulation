# Short simulations that check the trajectory logic rather than the metrics.

day <- 24 * 60
whole_run <- function(horizon) modifyList(SIM, list(warmup = 0, horizon = horizon))
simulate_alerts <- function(p, horizon, seed = 1) {
  env <- simulate_soc(p, horizon, seed)
  list(env = env,
       alerts = alert_table(get_mon_arrivals(env, ongoing = TRUE), get_mon_attributes(env), p,
                            whole_run(horizon)))
}

test_that("queues drain: every alert has a final outcome and only real incidents reach tier-2", {
  a <- simulate_alerts(baseline, 2 * day)$alerts
  expect_false(any(a$outcome == "still waiting"))
  expect_true(all(!is.na(a$escalated_at) == (a$true_positive & a$triaged)))
  expect_false(anyNA(a$investigation_wait[!is.na(a$escalated_at)]))
})

test_that("only low-severity alerts are auto-closed or expire, and only under load", {
  busy <- simulate_alerts(modifyList(baseline, list(alerts_per_hour = 30)), day)$alerts
  expect_gt(sum(busy$dropped), 0)
  expect_true(all(busy$severity[busy$dropped | busy$expired] == "low"))
  quiet <- simulate_alerts(modifyList(baseline, list(alerts_per_hour = 2)), day)$alerts
  expect_equal(sum(quiet$dropped | quiet$expired), 0)
})

test_that("common random numbers: staffing doesn't change which alerts arrive", {
  arrivals <- function(p) {
    a <- simulate_alerts(p, day, seed = 42)$alerts
    a[order(a$start_time), c("start_time", "severity", "true_positive")]
  }
  base <- arrivals(baseline)
  expect_equal(arrivals(SCENARIOS[[2]]), base, ignore_attr = TRUE)
  expect_equal(arrivals(SCENARIOS[[3]]), base, ignore_attr = TRUE)
})

test_that("detection tuning removes false positives only", {
  base <- simulate_alerts(baseline, 2 * day, seed = 3)$alerts
  tuned <- simulate_alerts(modifyList(baseline, list(fp_suppression = 0.25)), 2 * day, seed = 3)$alerts
  expect_setequal(tuned$start_time[tuned$true_positive], base$start_time[base$true_positive])
  expect_equal(nrow(tuned) / nrow(base), 0.75, tolerance = 0.05)
})

test_that("shift schedules set the number of analysts on duty", {
  p <- modifyList(baseline, list(tier1_analysts = c(1, 3, 2), tier2_analysts = c(1, 3, 2)))
  r <- get_mon_resources(simulate_alerts(p, day)$env)
  r <- r[r$resource == "tier1" & r$time < day, ]
  on_duty <- function(h) tail(r$capacity[r$time <= h * 60], 1)
  expect_equal(c(on_duty(3), on_duty(12), on_duty(20)), c(1, 3, 2))
})

test_that("an alert flood adds low-severity noise and exactly one planted real alert", {
  flood <- list(rate = 20, minutes = 120, plant_at = 60, start = 6 * 60)
  a <- simulate_alerts(modifyList(baseline, list(flood = flood)), day)$alerts
  base <- simulate_alerts(baseline, day)$alerts
  expect_equal(sum(a$planted), 1)
  planted <- a[a$planted, ]
  expect_equal(planted$start_time, flood$start + flood$plant_at)
  expect_true(planted$true_positive && planted$severity == "low")
  expect_gt(nrow(a) - nrow(base), 20)          # about 40 noise alerts expected
})
