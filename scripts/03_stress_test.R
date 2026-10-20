# Stress test: raise the alert rate until each staffing option misses its service targets.
# Same model and metrics as scripts 01-02, with STRESS$replications per point (R/params.R).

library(ggplot2)

stress_sim <- modifyList(SIM, list(replications = STRESS$replications))
grid <- expand.grid(rate = STRESS$alerts_per_hour, staffing = names(STRESS$staffing),
                    stringsAsFactors = FALSE)

stress <- do.call(rbind, lapply(seq_len(nrow(grid)), function(i) {
  g <- grid[i, ]
  staff <- STRESS$staffing[[g$staffing]]
  p <- modifyList(baseline, list(alerts_per_hour = g$rate,
                                 tier1_analysts = staff[1], tier2_analysts = staff[2]))
  message(sprintf("  stress: %s at %d alerts/hour", g$staffing, g$rate))
  envs <- run_scenario(p, stress_sim)
  a <- alert_table(get_mon_arrivals(envs, ongoing = TRUE), get_mon_attributes(envs), p)
  m <- replication_metrics(a, utilization(get_mon_resources(envs)))
  m$low_unreviewed <- m$low_auto_closed + m$low_expired
  cbind(g, summarise_metrics(m), row.names = NULL)
}))
write.csv(stress, "outputs/stress_test.csv", row.names = FALSE)

# ---- Capacity from first principles (no dropped alerts) -----------------------------
tri_mean <- vapply(baseline$triage_time, function(t) sum(t) / 3, 0)   # triangular mean
sev <- names(baseline$severity_mix)
triage_min_per_alert <- sum(baseline$severity_mix * tri_mean[sev])
incidents_per_alert <- sum(baseline$severity_mix * baseline$true_positive_rate[sev])
tier1_cap <- 60 / triage_min_per_alert                                   # alerts/hour per analyst
tier2_cap <- 60 / (baseline$investigation_mean * incidents_per_alert)    # alerts/hour per analyst

# ---- Breaking point: first rate at which any target is missed (on the mean) ---------
target_label <- c(
  sla_breach_high = sprintf("high-severity SLA breaches > %g%%", 100 * STRESS$targets[["sla_breach_high"]]),
  missed_incidents_per_week = sprintf("> %g real incident missed / week", STRESS$targets[["missed_incidents_per_week"]]),
  investigation_wait = sprintf("tier-2 wait > %g min", STRESS$targets[["investigation_wait"]])
)
value <- function(st, r, metric) {
  stress$mean[stress$staffing == st & stress$rate == r & stress$metric == metric]
}
breaking <- do.call(rbind, lapply(names(STRESS$staffing), function(st) {
  missed <- lapply(STRESS$alerts_per_hour, function(r) {
    names(STRESS$targets)[vapply(names(STRESS$targets),
                                 function(k) value(st, r, k) > STRESS$targets[[k]], logical(1))]
  })
  fails <- which(lengths(missed) > 0)
  staff <- STRESS$staffing[[st]]
  data.frame(
    staffing = st,
    capacity = sprintf("%.1f / %.1f", staff[1] * tier1_cap, staff[2] * tier2_cap),
    last_ok = if (length(fails) == 0) max(STRESS$alerts_per_hour)
              else if (fails[1] == 1) NA else STRESS$alerts_per_hour[fails[1] - 1],
    first_fail = if (length(fails) == 0) NA else STRESS$alerts_per_hour[fails[1]],
    targets_missed = if (length(fails) == 0) "none in range"
                     else paste(target_label[missed[[fails[1]]]], collapse = "; ")
  )
}))
names(breaking) <- c("staffing (tier-1 + tier-2)", "capacity, alerts/hour (tier-1 / tier-2)",
                     "highest rate meeting all targets", "first rate that fails", "targets missed there")

# ---- Tables: one metric per table, staffing x alert rate ----------------------------
rate_table <- function(metric, fmt) {
  out <- data.frame(staffing = names(STRESS$staffing))
  for (r in STRESS$alerts_per_hour) {
    out[[as.character(r)]] <- vapply(names(STRESS$staffing),
                                     function(st) fmt(value(st, r, metric)), "")
  }
  out
}
pct <- function(x) sprintf("%.1f%%", 100 * x)
num <- function(x) sprintf("%.1f", x)

# ---- Figure ----------------------------------------------------------------------------
panels <- c(sla_breach_high = "High alerts triaged late (%)",
            low_unreviewed = "Low alerts never reviewed (%)",
            missed_incidents_per_week = "Real incidents missed per week",
            investigation_wait = "Tier-2 wait for a confirmed incident (min)")
fig <- stress[stress$metric %in% names(panels), ]
share <- fig$metric %in% c("sla_breach_high", "low_unreviewed")
fig[share, c("mean", "lower", "upper")] <- 100 * fig[share, c("mean", "lower", "upper")]
fig$lower <- pmax(fig$lower, 0)
fig$panel <- factor(panels[fig$metric], levels = panels)
fig$staffing <- factor(fig$staffing, levels = names(STRESS$staffing))
targets_df <- data.frame(
  panel = factor(panels[names(STRESS$targets)], levels = panels),
  y = STRESS$targets * ifelse(names(STRESS$targets) == "sla_breach_high", 100, 1)
)
p_stress <- ggplot(fig, aes(rate, mean, colour = staffing, fill = staffing)) +
  geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.15, colour = NA) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.6) +
  geom_hline(data = targets_df, aes(yintercept = y), linetype = 2, colour = "grey30") +
  facet_wrap(~panel, scales = "free_y", ncol = 2) +
  scale_colour_manual(values = c("#2b6cb0", "#dd6b20", "#2f855a", "#805ad5"), name = "Analysts") +
  scale_fill_manual(values = c("#2b6cb0", "#dd6b20", "#2f855a", "#805ad5"), name = "Analysts") +
  scale_x_continuous(breaks = STRESS$alerts_per_hour) +
  labs(title = "Stress test: where each staffing option breaks",
       subtitle = sprintf("Mean of %d replications x %d days, 95%% CI. Dashed line = service target.",
                          STRESS$replications, SIM$days),
       x = "Alerts per hour", y = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
save_plot(p_stress, "stress_test.png", 10, 7)

report_add(
  "## 3. Stress test\n\n",
  sprintf("Alert rate swept from %d to %d per hour for four staffing options (%d replications x %d days per point). ",
          min(STRESS$alerts_per_hour), max(STRESS$alerts_per_hour), STRESS$replications, SIM$days),
  "Everything else stays at the baseline values. ",
  sprintf("Targets: at most %g%% of high-severity alerts triaged late, at most %g real incident missed per week, and a tier-2 wait of at most %g min.\n\n",
          100 * STRESS$targets[["sla_breach_high"]], STRESS$targets[["missed_incidents_per_week"]],
          STRESS$targets[["investigation_wait"]]),
  sprintf("Capacity if no alert were dropped: each tier-1 analyst triages %.1f alerts/hour (%.1f min per alert on average); ",
          tier1_cap, triage_min_per_alert),
  sprintf("each tier-2 analyst keeps up with %.1f alerts/hour (%.0f%% of alerts are real incidents, %d min each). ",
          tier2_cap, 100 * incidents_per_alert, baseline$investigation_mean),
  "Past tier-2 capacity its queue grows without limit, so the waits reported there depend on run length.\n\n",
  "### Breaking points\n\n", paste(md_table(breaking), collapse = "\n"), "\n\n",
  "![Stress test](figures/stress_test.png)\n\n",
  "### Real incidents missed per week\n\n",
  paste(md_table(rate_table("missed_incidents_per_week", num)), collapse = "\n"), "\n\n",
  "### Tier-2 wait for a confirmed incident (min)\n\n",
  paste(md_table(rate_table("investigation_wait", num)), collapse = "\n"), "\n\n",
  "### High-severity alerts triaged late\n\n",
  paste(md_table(rate_table("sla_breach_high", pct)), collapse = "\n"), "\n\n",
  "### Low-severity alerts never reviewed (auto-closed or expired)\n\n",
  paste(md_table(rate_table("low_unreviewed", pct)), collapse = "\n"), "\n"
)
