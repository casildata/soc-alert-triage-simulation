# Daily cycle, shift schedules and an alert flood.
# Same model and metrics as scripts 01-03; all settings are in DAY (R/params.R).

library(ggplot2)

day_sim <- modifyList(SIM, list(replications = DAY$replications))
shift_hours <- diff(c(baseline$shift_start, 24))
seat_hours <- function(x) if (length(x) == 1) 24 * x else sum(x * shift_hours)
on_duty <- function(x, hour) if (length(x) == 1) x else x[findInterval(hour, baseline$shift_start)]
staffed <- function(name, x, ...) {
  modifyList(baseline, list(name = name, hourly_profile = DAY$hourly_profile,
                            tier1_analysts = x, tier2_analysts = x, ...))
}

# ---- Daily cycle: whole-week metrics and metrics by hour of arrival -----------------------
daily <- lapply(names(DAY$staffing), function(st) {
  p <- staffed(st, DAY$staffing[[st]])
  message("  daily cycle: ", st)
  envs <- run_scenario(p, day_sim)
  a <- alert_table(get_mon_arrivals(envs, ongoing = TRUE), get_mon_attributes(envs), p, day_sim)
  a$hour <- (a$start_time %/% 60) %% 24
  m <- replication_metrics(a, utilization(get_mon_resources(envs), day_sim), day_sim)
  m$low_unreviewed <- m$low_auto_closed + m$low_expired
  by_hour <- do.call(rbind, lapply(split(a, a$hour), function(d) {
    lo <- d$severity == "low"
    data.frame(hour = d$hour[1],
               alerts_per_hour = nrow(d) / (day_sim$replications * (day_sim$days - 1)),
               investigation_wait = mean(d$investigation_wait, na.rm = TRUE),
               low_unreviewed = mean(d$dropped[lo] | d$expired[lo]))
  }))
  list(staffing = st, summary = summarise_metrics(m), by_hour = cbind(staffing = st, by_hour))
})

daily_summary <- do.call(rbind, lapply(daily, function(d) cbind(staffing = d$staffing, d$summary)))
write.csv(daily_summary, "outputs/daily_cycle.csv", row.names = FALSE)
by_hour <- do.call(rbind, lapply(daily, `[[`, "by_hour"))
write.csv(by_hour, "outputs/daily_cycle_by_hour.csv", row.names = FALSE)

day_value <- function(st, metric, col = "mean") {
  daily_summary[[col]][daily_summary$staffing == st & daily_summary$metric == metric]
}
daily_table <- do.call(rbind, lapply(names(DAY$staffing), function(st) {
  x <- DAY$staffing[[st]]
  h <- by_hour[by_hour$staffing == st, ]
  worst <- h[which.max(h$investigation_wait), ]
  meets <- all(vapply(names(STRESS$targets), function(k) day_value(st, k) <= STRESS$targets[[k]], logical(1)))
  data.frame(
    staffing = st,
    analyst_hours = 2 * seat_hours(x),
    fte = sprintf("%.0f", 2 * seat_hours(x) * 365 / 2080),
    tier2_wait = sprintf("%.0f (P90 %.0f)", day_value(st, "investigation_wait"),
                         day_value(st, "investigation_wait_p90")),
    worst_hour = sprintf("%.0f at %02d:00", worst$investigation_wait, worst$hour),
    high_late = sprintf("%.1f%%", 100 * day_value(st, "sla_breach_high")),
    low_unreviewed = sprintf("%.1f%%", 100 * day_value(st, "low_unreviewed")),
    missed = sprintf("%.1f", day_value(st, "missed_incidents_per_week")),
    meets = if (meets) "yes" else "no"
  )
}))
names(daily_table) <- c("staffing (per tier: night / day / evening)", "analyst-hours per day (both tiers)",
                        "approx. FTE", "tier-2 wait, min", "worst hour (tier-2 wait)",
                        "high alerts late", "low alerts never reviewed", "real incidents missed / week",
                        "meets all targets")

# ---- Figure: the day, hour by hour -----------------------------------------------------------
panels <- c(alerts = "Alerts arriving per hour", analysts = "Analysts on duty (each tier)",
            wait = "Tier-2 wait for a confirmed incident (min)", unreviewed = "Low alerts never reviewed (%)")
long <- rbind(
  data.frame(staffing = by_hour$staffing, hour = by_hour$hour, panel = panels[["wait"]],
             value = by_hour$investigation_wait),
  data.frame(staffing = by_hour$staffing, hour = by_hour$hour, panel = panels[["unreviewed"]],
             value = 100 * by_hour$low_unreviewed),
  do.call(rbind, lapply(seq_along(DAY$staffing), function(i) {
    st <- names(DAY$staffing)[i]
    offset <- (i - (length(DAY$staffing) + 1) / 2) * 0.04   # keep overlapping steps visible
    data.frame(staffing = st, hour = 0:24, panel = panels[["analysts"]],
               value = vapply(0:24 %% 24, function(h) on_duty(DAY$staffing[[st]], h), 0) + offset)
  }))
)
arrivals <- by_hour[by_hour$staffing == names(DAY$staffing)[1], ]
arrivals <- data.frame(hour = c(arrivals$hour, 24), value = c(arrivals$alerts_per_hour, NA),
                       panel = panels[["alerts"]])
long$panel <- factor(long$panel, levels = panels)
arrivals$panel <- factor(arrivals$panel, levels = panels)
long$staffing <- factor(long$staffing, levels = names(DAY$staffing))
colours <- c("#2b6cb0", "#dd6b20", "#2f855a", "#805ad5")
p_day <- ggplot() +
  geom_step(data = arrivals, aes(hour, value), colour = "grey35", linewidth = 0.8, na.rm = TRUE) +
  geom_step(data = long[long$panel == panels[["analysts"]], ],
            aes(hour, value, colour = staffing), linewidth = 0.9) +
  geom_line(data = long[!long$panel %in% panels[["analysts"]], ],
            aes(hour + 0.5, value, colour = staffing), linewidth = 0.8) +
  geom_hline(data = data.frame(panel = factor(panels[["wait"]], levels = panels),
                               y = STRESS$targets[["investigation_wait"]]),
             aes(yintercept = y), linetype = 2, colour = "grey30") +
  facet_wrap(~panel, scales = "free_y", ncol = 2, drop = FALSE) +
  scale_colour_manual(values = colours, name = NULL) +
  scale_x_continuous(breaks = seq(0, 24, 3), labels = sprintf("%02d:00", seq(0, 24, 3))) +
  labs(title = "A day in the SOC: same average load, different staffing",
       subtitle = sprintf("Mean over %d replications x %d days by hour of arrival. Dashed line = 60-minute tier-2 target.",
                          DAY$replications, SIM$days - 1),
       x = NULL, y = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
save_plot(p_day, "daily_cycle.png", 10, 7)

# ---- Alert flood: does a real alert survive 2 hours of noise? ------------------------------
f <- DAY$flood
flood_sim <- modifyList(SIM, list(replications = f$replications, days = f$days,
                                  horizon = f$days * 24 * 60))
wilson <- function(k, n, z = qnorm(0.975)) {
  centre <- (k + z^2 / 2) / (n + z^2); half <- z * sqrt(k * (n - k) / n + z^2 / 4) / (n + z^2)
  c(centre - half, centre + half)
}
flood_grid <- expand.grid(start = names(f$start_hour), noise = c("flood", "no flood"),
                          staffing = names(DAY$staffing), stringsAsFactors = FALSE)
flood <- do.call(rbind, lapply(seq_len(nrow(flood_grid)), function(i) {
  g <- flood_grid[i, ]
  start <- (24 + f$start_hour[[g$start]]) * 60
  p <- staffed(g$staffing, DAY$staffing[[g$staffing]],
               flood = list(rate = if (g$noise == "flood") f$rate else 0, minutes = f$minutes,
                            plant_at = f$plant_at, start = start))
  message(sprintf("  flood: %s, %s, %s", g$staffing, g$start, g$noise))
  envs <- run_scenario(p, flood_sim)
  a <- alert_table(get_mon_arrivals(envs, ongoing = TRUE), get_mon_attributes(envs), p, flood_sim)
  planted <- a[a$planted, ]
  missed <- sum(!planted$triaged)
  ci <- wilson(missed, nrow(planted))
  during <- a[a$start_time >= start & a$start_time < start + f$minutes & a$severity == "low", ]
  cbind(g, n = nrow(planted), missed = missed, p_missed = missed / nrow(planted),
        lower = ci[1], upper = ci[2],
        median_wait = median(planted$triage_wait, na.rm = TRUE),
        low_unreviewed_during = mean(!during$triaged))
}))
write.csv(flood, "outputs/flood.csv", row.names = FALSE)

fl <- flood[flood$noise == "flood", ]
nf <- flood[flood$noise == "no flood", ]
flood_table <- do.call(rbind, lapply(names(DAY$staffing), function(st) {
  row <- function(d, s) d[d$staffing == st & d$start == s, ]
  cells <- unlist(lapply(names(f$start_hour), function(s) {
    x <- row(fl, s); y <- row(nf, s)
    c(sprintf("%.0f%% (%.0f–%.0f)", 100 * x$p_missed, 100 * x$lower, 100 * x$upper),
      sprintf("%.0f%%", 100 * y$p_missed))
  }))
  data.frame(t(unname(c(st, cells))))
}))
names(flood_table) <- c("staffing", unlist(lapply(names(f$start_hour), function(s) {
  c(paste0("flood at ", s, ": real alert never reviewed (95% CI)"), "same alert, no flood")
})))

fl$staffing <- factor(fl$staffing, levels = rev(names(DAY$staffing)))
p_flood <- ggplot(fl, aes(100 * p_missed, staffing, colour = start)) +
  geom_errorbar(aes(xmin = 100 * lower, xmax = 100 * upper), width = 0.2, orientation = "y",
                position = position_dodge(width = 0.5)) +
  geom_point(size = 2.4, position = position_dodge(width = 0.5)) +
  scale_colour_manual(values = c("#2d3748", "#dd6b20"), name = "Flood starts at") +
  scale_x_continuous(limits = c(0, 100)) +
  labs(title = "Alert flood: chance a real alert is never reviewed",
       subtitle = sprintf(paste0("%d low-severity noise alerts/hour for %d min; one real low-severity ",
                                 "alert arrives %d min in.\n%d replications, 95%% CI."),
                          f$rate, f$minutes, f$plant_at, f$replications),
       x = "Real alert auto-closed or expired (%)", y = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
save_plot(p_flood, "alert_flood.png", 9, 4.5)

report_add(
  "## 4. Daily cycle, shifts and an alert flood\n\n",
  sprintf("Same average load as the baseline (%d alerts/hour), but following a daily profile: ", baseline$alerts_per_hour),
  sprintf("%.1f/hour at night, peaking at %.1f/hour in business hours. ",
          baseline$alerts_per_hour * min(DAY$hourly_profile) / mean(DAY$hourly_profile),
          baseline$alerts_per_hour * max(DAY$hourly_profile) / mean(DAY$hourly_profile)),
  sprintf("Shifts: night %02d:00-%02d:00, day %02d:00-%02d:00, evening %02d:00-24:00; the same number of analysts in each tier. ",
          baseline$shift_start[1], baseline$shift_start[2], baseline$shift_start[2], baseline$shift_start[3],
          baseline$shift_start[3]),
  sprintf("%d replications x %d days per option (first day discarded). ", DAY$replications, SIM$days),
  "FTE assumes 2,080 paid hours a year per person, before leave and training.\n\n",
  paste(md_table(daily_table), collapse = "\n"), "\n\n",
  "![Daily cycle](figures/daily_cycle.png)\n\n",
  "### Alert flood\n\n",
  sprintf(paste0("On day 2, %d extra low-severity false positives per hour arrive for %d minutes, and one real ",
                 "low-severity alert (the intrusion the flood is meant to hide) arrives %d minutes in. "),
          f$rate, f$minutes, f$plant_at),
  sprintf("%d replications per cell; \"no flood\" plants the same alert without the noise. ", f$replications),
  "Intervals are Wilson 95% intervals.\n\n",
  paste(md_table(flood_table), collapse = "\n"), "\n\n",
  "![Alert flood](figures/alert_flood.png)\n"
)
