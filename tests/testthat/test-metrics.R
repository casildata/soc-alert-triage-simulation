# Metrics on hand-built monitor tables in simmer's column layout (no simulation needed).

sim <- modifyList(SIM, list(warmup = 0, horizon = 1000))
p <- baseline

arrivals <- data.frame(
  name = c("a1", "a2", "a3", "a4", "a5", "a6"),
  start_time = c(10, 20, 30, 40, 50, 990),
  end_time = c(30, 20, 120, 200, NA, NA),
  activity_time = c(8, 0, 0, 70, NA, NA),
  finished = c(TRUE, FALSE, FALSE, TRUE, NA, NA),
  replication = 1
)
att <- function(name, key, value) data.frame(time = 0, name = name, key = key, value = value,
                                            replication = 1)
attributes <- rbind(
  # a1: high, triaged after 20 min (SLA 15 -> breach), false positive
  att("a1", "severity", 3), att("a1", "true_positive", 0), att("a1", "triage_start", 30),
  # a2: low, auto-closed on arrival, was a real incident -> missed
  att("a2", "severity", 1), att("a2", "true_positive", 1), att("a2", "dropped", 1),
  # a3: low, not dropped, expired unreviewed
  att("a3", "severity", 1), att("a3", "true_positive", 0), att("a3", "dropped", 0),
  att("a3", "expired", 1),
  # a4: medium, triaged after 10 min, escalated, waited 15 min for tier-2
  att("a4", "severity", 2), att("a4", "true_positive", 1), att("a4", "triage_start", 50),
  att("a4", "escalated_at", 60), att("a4", "investigation_start", 75),
  # a5: high, still waiting at the end of a cut-short run, 950 min > 15 min SLA -> known breach
  att("a5", "severity", 3), att("a5", "true_positive", 0),
  # a6: medium, still waiting, only 10 min so far < 60 min SLA -> unknown
  att("a6", "severity", 2), att("a6", "true_positive", 0)
)

a <- alert_table(arrivals, attributes, p, sim)
a <- a[order(a$name), ]

test_that("severity codes map to labels", {
  expect_identical(as.character(a$severity), c("high", "low", "low", "medium", "high", "medium"))
})

test_that("outcomes are classified", {
  expect_identical(a$outcome, c("triaged", "auto-closed (backlog)", "expired unreviewed", "triaged",
                                "still waiting", "still waiting"))
})

test_that("triage wait is triage start minus arrival", {
  expect_equal(a$triage_wait[c(1, 4)], c(20, 10))
})

test_that("SLA breaches include censored alerts", {
  expect_identical(a$sla_breach, c(TRUE, TRUE, TRUE, FALSE, TRUE, NA))
})

test_that("only real incidents that were dropped or expired count as missed", {
  expect_identical(a$missed_incident, c(FALSE, TRUE, FALSE, FALSE, FALSE, FALSE))
})

test_that("tier-2 wait is investigation start minus escalation", {
  expect_equal(a$investigation_wait[4], 15)
})

test_that("the measurement window drops warm-up arrivals and arrivals after the horizon", {
  aw <- alert_table(arrivals, attributes, p, modifyList(sim, list(warmup = 15, horizon = 900)))
  expect_setequal(aw$name, c("a2", "a3", "a4", "a5"))
})

test_that("utilization is time-weighted over the window", {
  # 1 of 2 servers busy for the first half of the horizon -> 25%
  resources <- data.frame(resource = "tier1", time = c(0, 500), server = c(1, 0), queue = 0,
                          capacity = 2, queue_size = Inf, system = c(1, 0), limit = Inf,
                          replication = 1)
  expect_equal(utilization(resources, sim)$utilization, 0.25)
  # Shifts: 1 analyst busy throughout; capacity 1 for the first half, then 3 -> 1000 / 2000
  shifts <- transform(resources, server = c(1, 1), capacity = c(1, 3))
  expect_equal(utilization(shifts, sim)$utilization, 0.5)
  # Events after the horizon (the drain) don't count
  drained <- rbind(resources, transform(resources[1, ], time = 1200, server = 2))
  expect_equal(utilization(drained, sim)$utilization, 0.25)
})

test_that("low-severity drop and expiry shares and the high SLA breach share", {
  u <- data.frame(replication = 1, resource = "tier1", utilization = 0.25)
  m <- replication_metrics(a, u, sim)
  expect_equal(m$low_auto_closed, 0.5)
  expect_equal(m$low_expired, 0.5)
  expect_equal(m$sla_breach_high, 1)
})

test_that("the CI brackets the mean", {
  s <- summarise_metrics(data.frame(replication = 1:4, x = c(1, 2, 3, 4)))
  expect_equal(s$mean, 2.5)
  expect_lt(s$lower, 2.5)
  expect_gt(s$upper, 2.5)
})
