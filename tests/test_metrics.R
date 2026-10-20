# Tests for the metrics code, using hand-built monitor tables in simmer's column layout.
# No simulation (and no simmer) needed:  Rscript tests/test_metrics.R

source("R/params.R")
source("R/metrics.R")

sim <- modifyList(SIM, list(warmup = 0, cooldown = 0, horizon = 1000))
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
  # a5: high, still waiting at the end, already 950 min > 15 min SLA -> known breach
  att("a5", "severity", 3), att("a5", "true_positive", 0),
  # a6: medium, still waiting, only 10 min so far < 60 min SLA -> unknown
  att("a6", "severity", 2), att("a6", "true_positive", 0)
)

a <- alert_table(arrivals, attributes, p, sim)
a <- a[order(a$name), ]
check <- function(cond, msg) if (!isTRUE(cond)) stop("FAIL: ", msg) else cat("PASS ", msg, "\n")

check(identical(as.character(a$severity), c("high", "low", "low", "medium", "high", "medium")),
      "severity codes map to labels")
check(identical(a$outcome, c("triaged", "auto-closed (backlog)", "expired unreviewed", "triaged",
                             "still waiting", "still waiting")), "outcome classification")
check(isTRUE(all.equal(a$triage_wait[c(1, 4)], c(20, 10))), "triage wait = triage_start - arrival")
check(identical(a$sla_breach, c(TRUE, TRUE, TRUE, FALSE, TRUE, NA)),
      "SLA breach, including censored alerts")
check(identical(a$missed_incident, c(FALSE, TRUE, FALSE, FALSE, FALSE, FALSE)),
      "only real incidents that were dropped/expired count as missed")
check(isTRUE(all.equal(a$investigation_wait[4], 15)), "tier-2 wait = start - escalation")

# Measurement window drops warm-up and cool-down arrivals
sim_w <- modifyList(sim, list(warmup = 15, cooldown = 100))
aw <- alert_table(arrivals, attributes, p, sim_w)
check(setequal(aw$name, c("a2", "a3", "a4", "a5")), "warm-up / cool-down window")

# Utilization: 1 of 2 servers busy for the first half of the horizon -> 25%
resources <- data.frame(resource = "tier1", time = c(0, 500), server = c(1, 0), queue = 0,
                        capacity = 2, queue_size = Inf, system = c(1, 0), limit = Inf,
                        replication = 1)
u <- utilization(resources, sim)
check(isTRUE(all.equal(u$utilization, 0.25)), "time-weighted utilization")

m <- replication_metrics(a, u, sim)
check(isTRUE(all.equal(m$low_auto_closed, 0.5)) && isTRUE(all.equal(m$low_expired, 0.5)),
      "low-severity drop and expiry shares")
check(isTRUE(all.equal(m$sla_breach_high, 1)), "high SLA breach share")

s <- summarise_metrics(data.frame(replication = 1:4, x = c(1, 2, 3, 4)))
check(isTRUE(all.equal(s$mean, 2.5)) && s$lower < 2.5 && s$upper > 2.5, "CI brackets the mean")
cat("\nAll metric tests passed\n")
