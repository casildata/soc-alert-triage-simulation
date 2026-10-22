# Model parameters. All times are in minutes. Values are illustrative assumptions for a
# small SOC, not benchmarks; edit them to match your own alert data.

baseline <- list(
  name = "Baseline",
  alerts_per_hour = 10,
  # Relative alert rate by hour of day (00:00 first), rescaled to average 1. Flat here;
  # scripts/04_daily_cycle.R uses DAY$hourly_profile.
  hourly_profile = rep(1, 24),
  severity_mix = c(high = 0.10, medium = 0.30, low = 0.60),
  # Tier-1 triage time: triangular (min, mode, max)
  triage_time = list(high = c(5, 10, 25), medium = c(4, 8, 20), low = c(2, 5, 12)),
  # Share of alerts that turn out to be real incidents (hidden until triage)
  true_positive_rate = c(high = 0.50, medium = 0.20, low = 0.05),
  # Tier-2 investigation time: gamma with this mean and shape
  investigation_mean = 60,
  investigation_shape = 4,
  # Analysts on duty: one number around the clock, or one per shift (shifts start at
  # shift_start hours)
  tier1_analysts = 2,
  tier2_analysts = 2,
  shift_start = c(night = 0, day = 7, evening = 17),
  # Share of all alerts removed by detection tuning (false positives only)
  fp_suppression = 0,
  # Serve higher severities first in both tiers (FALSE: first come, first served)
  priorities = TRUE,
  # Balking: low-severity alerts are auto-closed unreviewed when the tier-1 backlog is this long
  balk_queue_length = 15,
  # Reneging: a low-severity alert still waiting after U(min, max) minutes expires unreviewed
  low_expiry = c(60, 120),
  # Service level: triage should start within this many minutes. The low-severity SLA is
  # never reached in practice: a low alert expires (low_expiry) before it has waited 240 min.
  triage_sla = c(high = 15, medium = 60, low = 240)
)

scenario <- function(name, ...) modifyList(baseline, c(list(name = name), list(...)))

SCENARIOS <- list(
  baseline,
  scenario("+1 tier-1 analyst", tier1_analysts = 3),
  scenario("+1 tier-2 analyst", tier2_analysts = 3),
  # Tuning removes false positives only, so true incidents per hour stay the same
  scenario("Detection tuning (-25% alerts)", fp_suppression = 0.25),
  scenario("SOAR enrichment (low triage 2x faster)",
           triage_time = modifyList(baseline$triage_time, list(low = c(1, 2.5, 6))))
)

SIM <- list(
  replications = 100,
  days = 5,
  warmup = 1 * 24 * 60,   # discard the first day (the SOC starts empty)
  seed = 7339             # arrivals stop after `days`; queues then drain, so no outcome is censored
)
SIM$horizon <- SIM$days * 24 * 60

# Stress test (scripts/03_stress_test.R): alert rates to sweep, staffing options as
# c(tier-1, tier-2) analysts, and the service targets that define a "breaking point".
STRESS <- list(
  alerts_per_hour = seq(10, 22, by = 2),
  staffing = list("2 + 2 (baseline)" = c(2, 2),
                  "3 + 2 (+1 tier-1)" = c(3, 2),
                  "2 + 3 (+1 tier-2)" = c(2, 3),
                  "3 + 3 (+1 each)"   = c(3, 3)),
  replications = 30,
  targets = c(sla_breach_high = 0.05,          # share of high alerts triaged late
              missed_incidents_per_week = 1,   # real incidents auto-closed or expired
              investigation_wait = 60)         # minutes a confirmed incident waits for tier-2
)

# Daily cycle, shifts and an alert flood (scripts/04_daily_cycle.R). Same average load as the
# baseline (10 alerts/hour), but busier in business hours and quieter at night.
DAY <- list(
  hourly_profile = c(rep(0.5, 7), 0.8, rep(1.6, 9), rep(1.0, 3), rep(0.6, 4)),
  # Analysts on duty per shift (night 00-07, day 07-17, evening 17-24), the same in both tiers
  staffing = list("2 + 2 around the clock" = 2,
                  "Shifts 1 / 3 / 2"       = c(1, 3, 2),
                  "Shifts 2 / 3 / 2"       = c(2, 3, 2),
                  "3 + 3 around the clock" = 3),
  replications = 50,
  # Alert flood: low-severity noise at `rate` per hour for `minutes`, hiding one real
  # low-severity alert planted `plant_at` minutes in. Day 1 is warm-up; the flood starts on
  # day 2 at each of `start_hour`.
  flood = list(rate = 20, minutes = 120, plant_at = 60,
               start_hour = c("02:00 (night shift)" = 2, "10:00 (day shift)" = 10),
               replications = 100, days = 2)
)

SEVERITY <- c("1" = "low", "2" = "medium", "3" = "high")
