# Model parameters. All times are in minutes. Values are illustrative assumptions for a
# small SOC, not benchmarks; edit them to match your own alert data.

baseline <- list(
  name = "Baseline",
  alerts_per_hour = 10,
  severity_mix = c(high = 0.10, medium = 0.30, low = 0.60),
  # Tier-1 triage time: triangular (min, mode, max)
  triage_time = list(high = c(5, 10, 25), medium = c(4, 8, 20), low = c(2, 5, 12)),
  # Share of alerts that turn out to be real incidents (hidden until triage)
  true_positive_rate = c(high = 0.50, medium = 0.20, low = 0.05),
  # Tier-2 investigation time: gamma with this mean and shape
  investigation_mean = 60,
  investigation_shape = 4,
  tier1_analysts = 2,
  tier2_analysts = 2,
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
  scenario("Detection tuning (-25% alerts)", alerts_per_hour = 7.5,
           true_positive_rate = baseline$true_positive_rate / 0.75),
  scenario("SOAR enrichment (low triage 2x faster)",
           triage_time = modifyList(baseline$triage_time, list(low = c(1, 2.5, 6))))
)

SIM <- list(
  replications = 100,
  days = 5,
  warmup = 1 * 24 * 60,   # discard the first day (the SOC starts empty)
  cooldown = 4 * 60,      # ignore alerts arriving in the last 4 hours (outcome not yet known)
  seed = 7339
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

SEVERITY <- c("1" = "low", "2" = "medium", "3" = "high")
