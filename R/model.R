# Discrete-event model of a two-tier SOC in simmer.
#
#   alert ─► severity? ─► [low only: auto-close if backlog >= threshold] ─► tier-1 triage
#                          [low only: expire if not picked up in time]          │
#                                                      true positive? ──yes──► tier-2 investigation
#
# Every alert's random inputs (arrival time, severity, ground truth, service times, expiry)
# are drawn before the simulation starts, so replication i sees the same alerts in every
# staffing scenario (common random numbers). Arrivals stop at the horizon and the queues
# then drain, so every measured alert has a known outcome and no wait is censored.
# Every trajectory closure refers to the `env` created inside simulate_soc(), so each
# replication reads its own queue lengths and attributes (the coursework version read a
# global `env` shared by all replications).

library(simmer)

SEVERITY_LEVELS <- c(high = 3, medium = 2, low = 1)   # also the queue priority

qtriangle <- function(u, a, c, b) {
  fc <- (c - a) / (b - a)
  ifelse(u < fc, a + sqrt(u * (b - a) * (c - a)), b - sqrt((1 - u) * (b - a) * (b - c)))
}

# One row per alert, sorted by arrival time (minutes). The random draws depend only on the
# seed, the alert rate and its daily profile, never on staffing.
draw_alerts <- function(p, horizon) {
  profile <- p$hourly_profile / mean(p$hourly_profile)
  rate_at <- function(t) p$alerts_per_hour / 60 * profile[(t %/% 60) %% 24 + 1]
  rate_max <- p$alerts_per_hour / 60 * max(profile)

  # Arrivals: a Poisson process at the peak rate, thinned to the hourly profile
  n <- qpois(1 - 1e-9, rate_max * horizon)
  time <- cumsum(rexp(n, rate_max))
  u <- matrix(runif(7 * n), n,
              dimnames = list(NULL, c("thin", "sev", "tp", "suppress", "triage", "inv", "expiry")))
  keep <- time < horizon & u[, "thin"] < rate_at(time) / rate_max
  time <- time[keep]; u <- u[keep, , drop = FALSE]

  sev <- c("high", "medium", "low")[findInterval(u[, "sev"], cumsum(p$severity_mix[c("high", "medium", "low")])) + 1]
  tp_rate <- p$true_positive_rate[sev]
  tp <- u[, "tp"] < tp_rate
  # Detection tuning removes a share of all alerts, false positives only
  suppressed <- !tp & u[, "suppress"] < p$fp_suppression / (1 - tp_rate)

  tri <- do.call(rbind, p$triage_time[sev])
  alerts <- data.frame(
    time = time,
    severity = unname(SEVERITY_LEVELS[sev]),
    true_positive = as.numeric(tp),
    triage_time = qtriangle(u[, "triage"], tri[, 1], tri[, 2], tri[, 3]),
    investigation_time = qgamma(u[, "inv"], shape = p$investigation_shape,
                                rate = p$investigation_shape / p$investigation_mean),
    expiry = p$low_expiry[1] + u[, "expiry"] * diff(p$low_expiry),
    planted = 0
  )[!suppressed, ]
  if (!is.null(p$flood)) alerts <- rbind(alerts, draw_flood(p))
  alerts[order(alerts$time), ]
}

# Alert flood: extra low-severity false positives at `rate` per hour for `minutes`, and one
# planted real low-severity alert (the intrusion the flood is meant to hide) at `plant_at`
# minutes into the flood. Drawn after the regular alerts, so those stay the same.
draw_flood <- function(p) {
  f <- p$flood
  n <- qpois(1 - 1e-9, f$rate / 60 * f$minutes)
  t <- f$start + cumsum(rexp(n, f$rate / 60))
  t <- c(t[t < f$start + f$minutes], f$start + f$plant_at)
  m <- length(t)
  tt <- p$triage_time$low
  data.frame(time = t, severity = SEVERITY_LEVELS[["low"]],
             true_positive = c(rep(0, m - 1), 1),
             triage_time = qtriangle(runif(m), tt[1], tt[2], tt[3]),
             investigation_time = qgamma(runif(m), shape = p$investigation_shape,
                                         rate = p$investigation_shape / p$investigation_mean),
             expiry = p$low_expiry[1] + runif(m) * diff(p$low_expiry),
             planted = c(rep(0, m - 1), 1))
}

# A fixed number of analysts, or one number per shift (shifts start at p$shift_start hours)
capacity <- function(analysts, p) {
  if (length(analysts) == 1) return(analysts)
  schedule(p$shift_start * 60, analysts, period = 24 * 60)
}

simulate_soc <- function(p, horizon, seed) {
  validate_params(p)
  set.seed(seed)
  alerts <- draw_alerts(p, horizon)
  env <- simmer(paste("SOC -", p$name))
  att <- function(key) function() get_attribute(env, key)

  investigate <- trajectory("tier-2 investigation") %>%
    set_attribute("escalated_at", function() now(env)) %>%
    seize("tier2", 1) %>%
    set_attribute("investigation_start", function() now(env)) %>%
    timeout_from_attribute("investigation_time") %>%
    release("tier2", 1)

  triage <- trajectory("tier-1 triage") %>%
    set_attribute("triage_start", function() now(env)) %>%
    timeout_from_attribute("triage_time") %>%
    release("tier1", 1) %>%
    branch(att("true_positive"), continue = TRUE, investigate)

  low <- trajectory("low severity") %>%
    # Balking: record the decision as an attribute first, so it shows up in the monitor
    set_attribute("dropped", function() {
      as.numeric(get_queue_count(env, "tier1") >= p$balk_queue_length)
    }) %>%
    leave(prob = att("dropped")) %>%
    # Reneging: give up waiting after the alert's expiry time
    renege_in(att("expiry"), out = trajectory("expired") %>% set_attribute("expired", 1)) %>%
    seize("tier1", 1) %>%
    renege_abort() %>%
    join(triage)

  high_or_medium <- trajectory("high or medium severity") %>%
    seize("tier1", 1) %>%
    join(triage)

  alert <- trajectory("alert") %>%
    # Higher value = served first; tier-1 and tier-2 are not preemptive
    set_prioritization(function() {
      s <- if (p$priorities) get_attribute(env, "severity") else 1
      c(s, s, 0)
    }) %>%
    branch(function() if (get_attribute(env, "severity") == SEVERITY_LEVELS[["low"]]) 1 else 2,
           continue = c(FALSE, FALSE), low, high_or_medium)

  env %>%
    add_resource("tier1", capacity(p$tier1_analysts, p)) %>%
    add_resource("tier2", capacity(p$tier2_analysts, p)) %>%
    add_dataframe("alert", alert, alerts, mon = 2, time = "absolute",
                  col_attributes = c("severity", "true_positive", "triage_time",
                                     "investigation_time", "expiry", "planted")) %>%
    run(until = horizon)
  # No arrivals after the horizon: let the queues drain (in steps, because a shift
  # schedule keeps generating events forever)
  in_system <- function() sum(get_server_count(env, c("tier1", "tier2")),
                              get_queue_count(env, c("tier1", "tier2")))
  while (in_system() > 0) env %>% run(until = now(env) + 60)
  wrap(env)
}

# Replication i uses seed + i in every scenario, so scenarios see the same alerts.
run_scenario <- function(p, sim = SIM) {
  lapply(seq_len(sim$replications), function(i) simulate_soc(p, sim$horizon, sim$seed + i))
}
