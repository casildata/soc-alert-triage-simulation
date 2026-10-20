# Turn simmer monitor tables into one row per alert, then into scenario metrics.
# Works on plain data frames, so it can be tested without running a simulation.

ATTRIBUTE_KEYS <- c("severity", "true_positive", "dropped", "expired", "triage_start",
                    "escalated_at", "investigation_start")

# arrivals:   get_mon_arrivals(envs, ongoing = TRUE)
#             columns name, start_time, end_time, activity_time, finished, replication
# attributes: get_mon_attributes(envs)
#             columns time, name, key, value, replication
alert_table <- function(arrivals, attributes, p, sim = SIM) {
  att <- attributes[attributes$key %in% ATTRIBUTE_KEYS, c("replication", "name", "key", "value")]
  wide <- reshape(att, idvar = c("replication", "name"), timevar = "key", direction = "wide")
  names(wide) <- sub("^value\\.", "", names(wide))
  for (k in setdiff(ATTRIBUTE_KEYS, names(wide))) wide[[k]] <- NA_real_

  a <- merge(arrivals[, c("replication", "name", "start_time", "end_time")], wide,
             by = c("replication", "name"), all.x = TRUE)
  # Measurement window: after warm-up, and early enough that the outcome is known
  a <- a[a$start_time >= sim$warmup & a$start_time <= sim$horizon - sim$cooldown, ]

  a$severity <- factor(SEVERITY[as.character(a$severity)], levels = c("high", "medium", "low"))
  a$dropped <- !is.na(a$dropped) & a$dropped == 1
  a$expired <- !is.na(a$expired) & a$expired == 1
  a$true_positive <- !is.na(a$true_positive) & a$true_positive == 1
  a$triaged <- !is.na(a$triage_start)
  a$outcome <- ifelse(a$dropped, "auto-closed (backlog)",
                      ifelse(a$expired, "expired unreviewed",
                             ifelse(a$triaged, "triaged", "still waiting")))
  a$triage_wait <- a$triage_start - a$start_time
  sla <- p$triage_sla[as.character(a$severity)]
  # Not yet triaged at the end of the run: a breach if it has already waited past the SLA,
  # otherwise unknown. Auto-closed and expired alerts never got triaged: a breach.
  waited_so_far <- sim$horizon - a$start_time
  a$sla_breach <- ifelse(a$triaged, a$triage_wait > sla,
                         ifelse(a$outcome == "still waiting",
                                ifelse(waited_so_far > sla, TRUE, NA), TRUE))
  a$investigation_wait <- a$investigation_start - a$escalated_at
  a$missed_incident <- a$true_positive & (a$dropped | a$expired)
  a
}

# Busy-time utilization from the resource monitor (server count is a step function)
utilization <- function(resources, sim = SIM) {
  per_rep <- lapply(split(resources, list(resources$replication, resources$resource), drop = TRUE),
                    function(r) {
    r <- r[order(r$time), ]
    t <- c(r$time, sim$horizon)
    busy <- sum(r$server * diff(t))
    data.frame(replication = r$replication[1], resource = r$resource[1],
               utilization = busy / (r$capacity[1] * sim$horizon))
  })
  do.call(rbind, per_rep)
}

# Per-replication metrics; the scenario estimate is the mean across replications.
replication_metrics <- function(a, util, sim = SIM) {
  window_days <- (sim$horizon - sim$cooldown - sim$warmup) / (24 * 60)
  per_rep <- lapply(split(a, a$replication), function(d) {
    hi <- d$severity == "high"; md <- d$severity == "medium"; lo <- d$severity == "low"
    data.frame(
      replication = d$replication[1],
      alerts_per_day = nrow(d) / window_days,
      wait_high = mean(d$triage_wait[hi], na.rm = TRUE),
      wait_medium = mean(d$triage_wait[md], na.rm = TRUE),
      wait_low = mean(d$triage_wait[lo], na.rm = TRUE),
      sla_breach_high = mean(d$sla_breach[hi], na.rm = TRUE),
      sla_breach_medium = mean(d$sla_breach[md], na.rm = TRUE),
      low_auto_closed = mean(d$dropped[lo]),
      low_expired = mean(d$expired[lo]),
      investigation_wait = mean(d$investigation_wait, na.rm = TRUE),
      missed_incidents_per_week = sum(d$missed_incident) / window_days * 7
    )
  })
  out <- do.call(rbind, per_rep)
  u <- reshape(util, idvar = "replication", timevar = "resource", direction = "wide")
  names(u) <- sub("^utilization\\.", "util_", names(u))
  merge(out, u, by = "replication", all.x = TRUE)
}

# Mean and 95% confidence interval across replications (t interval)
summarise_metrics <- function(rep_metrics) {
  cols <- setdiff(names(rep_metrics), c("replication", "scenario"))
  do.call(rbind, lapply(cols, function(m) {
    x <- rep_metrics[[m]]
    x <- x[is.finite(x)]
    n <- length(x)
    half <- if (n > 1) qt(0.975, n - 1) * sd(x) / sqrt(n) else NA_real_
    data.frame(metric = m, mean = mean(x), lower = mean(x) - half, upper = mean(x) + half, n = n)
  }))
}
