# Discrete-event model of a two-tier SOC in simmer.
#
#   alert ─► severity? ─► [low only: auto-close if backlog >= threshold] ─► tier-1 triage
#                          [low only: expire if not picked up in time]          │
#                                                      true positive? ──yes──► tier-2 investigation
#
# Every trajectory closure refers to the `env` created inside simulate_soc(), so each
# replication reads its own queue lengths and attributes (the coursework version read a
# global `env` shared by all replications).

library(simmer)

rtriangle <- function(n, a, c, b) {
  u <- runif(n)
  fc <- (c - a) / (b - a)
  ifelse(u < fc, a + sqrt(u * (b - a) * (c - a)), b - sqrt((1 - u) * (b - a) * (b - c)))
}

simulate_soc <- function(p, horizon, seed) {
  set.seed(seed)
  env <- simmer(paste("SOC -", p$name))

  triage_time <- function(sev) {
    tt <- p$triage_time[[sev]]
    function() rtriangle(1, tt[1], tt[2], tt[3])
  }
  investigation_time <- function() {
    rgamma(1, shape = p$investigation_shape, rate = p$investigation_shape / p$investigation_mean)
  }

  escalate <- trajectory("tier-2 investigation") %>%
    set_attribute("escalated_at", function() now(env)) %>%
    seize("tier2", 1) %>%
    set_attribute("investigation_start", function() now(env)) %>%
    timeout(investigation_time) %>%
    release("tier2", 1)

  path <- function(sev, priority) {
    trj <- trajectory(paste(sev, "severity")) %>%
      set_attribute("severity", priority) %>%
      set_attribute("true_positive", function() rbinom(1, 1, p$true_positive_rate[[sev]])) %>%
      # Higher value = served first; tier-1 and tier-2 are not preemptive
      set_prioritization(c(priority, priority, 0))
    if (sev == "low") {
      trj <- trj %>%
        # Balking: record the decision as an attribute first, so it shows up in the monitor
        set_attribute("dropped", function() {
          as.numeric(get_queue_count(env, "tier1") >= p$balk_queue_length)
        }) %>%
        leave(prob = function() get_attribute(env, "dropped")) %>%
        # Reneging: give up waiting after U(min, max) minutes
        renege_in(function() runif(1, p$low_expiry[1], p$low_expiry[2]),
                  out = trajectory("expired") %>% set_attribute("expired", 1))
    }
    trj <- trj %>% seize("tier1", 1)
    if (sev == "low") trj <- trj %>% renege_abort()
    trj %>%
      set_attribute("triage_start", function() now(env)) %>%
      timeout(triage_time(sev)) %>%
      release("tier1", 1) %>%
      branch(function() get_attribute(env, "true_positive"), continue = TRUE, escalate)
  }

  alert <- trajectory("alert") %>%
    branch(function() sample(1:3, 1, prob = p$severity_mix[c("high", "medium", "low")]),
           continue = c(TRUE, TRUE, TRUE),
           path("high", 3), path("medium", 2), path("low", 1))

  env %>%
    add_resource("tier1", p$tier1_analysts) %>%
    add_resource("tier2", p$tier2_analysts) %>%
    add_generator("alert", alert, function() rexp(1, p$alerts_per_hour / 60), mon = 2) %>%
    run(until = horizon) %>%
    wrap()
}

# Replication i uses the same seed in every scenario (common random numbers), so
# scenario differences are less noisy.
run_scenario <- function(p, sim = SIM) {
  lapply(seq_len(sim$replications), function(i) simulate_soc(p, sim$horizon, sim$seed + i))
}
