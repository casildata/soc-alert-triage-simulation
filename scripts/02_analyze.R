# Metrics, comparison tables and figures for all scenarios.

library(ggplot2)

alerts <- list()
rep_metrics <- list()
for (nm in names(sim_results)) {
  r <- sim_results[[nm]]
  a <- alert_table(r$arrivals, r$attributes, r$params)
  a$scenario <- nm
  alerts[[nm]] <- a
  m <- replication_metrics(a, utilization(r$resources))
  m$scenario <- nm
  rep_metrics[[nm]] <- m
}
rep_metrics_all <- do.call(rbind, rep_metrics)
write.csv(rep_metrics_all, "outputs/replication_metrics.csv", row.names = FALSE)

summary_long <- do.call(rbind, lapply(names(rep_metrics), function(nm) {
  s <- summarise_metrics(rep_metrics[[nm]][, setdiff(names(rep_metrics[[nm]]), "scenario")])
  s$scenario <- nm
  s
}))
write.csv(summary_long, "outputs/scenario_summary.csv", row.names = FALSE)

# ---- Comparison table ---------------------------------------------------------------
show <- c(
  wait_high = "Mean wait to triage, high (min)",
  wait_high_p90 = "P90 wait to triage, high (min)",
  sla_breach_high = "High alerts missing 15-min SLA",
  sla_breach_medium = "Medium alerts missing 60-min SLA",
  low_auto_closed = "Low alerts auto-closed (backlog)",
  low_expired = "Low alerts expired unreviewed",
  missed_incidents_per_week = "Real incidents missed / week",
  investigation_wait = "Wait for tier-2 (min)",
  investigation_wait_p90 = "P90 wait for tier-2 (min)",
  util_tier1 = "Tier-1 utilization",
  util_tier2 = "Tier-2 utilization"
)
is_share <- c("sla_breach_high", "sla_breach_medium", "low_auto_closed", "low_expired",
              "util_tier1", "util_tier2")
fmt_cell <- function(row) {
  lower <- max(row$lower, 0)   # a t-interval on a share near zero can dip below it
  if (row$metric %in% is_share) {
    sprintf("%.1f%% (%.1f–%.1f)", 100 * row$mean, 100 * lower, 100 * row$upper)
  } else {
    sprintf("%.1f (%.1f–%.1f)", row$mean, lower, row$upper)
  }
}
cmp <- data.frame(metric = unname(show))
for (nm in names(sim_results)) {
  s <- summary_long[summary_long$scenario == nm, ]
  cmp[[nm]] <- vapply(names(show), function(k) fmt_cell(s[s$metric == k, ]), "")
}

# ---- Paired differences: every scenario sees the same alerts (common random numbers) ---
by_rep <- function(m, metric) m[[metric]][order(m$replication)]
paired <- do.call(rbind, lapply(names(sim_results)[-1], function(nm) {
  d <- by_rep(rep_metrics[[nm]], "investigation_wait") - by_rep(rep_metrics[[1]], "investigation_wait")
  ci <- summarise_metrics(data.frame(replication = seq_along(d), d = d))
  data.frame(scenario = nm, change = sprintf("%+.2f (%+.2f to %+.2f)", ci$mean, ci$lower, ci$upper))
}))
names(paired) <- c("scenario", "change in tier-2 wait vs. baseline, min (paired 95% CI)")

# ---- Check against the analytic tier-1 wait: the baseline without priorities ----------
tier1_wait <- function(a) {
  w <- tapply(a$triage_wait, a$replication, mean, na.rm = TRUE)
  s <- summarise_metrics(data.frame(replication = seq_along(w), wait = as.numeric(w)))
  sprintf("%.2f (%.2f–%.2f)", s$mean, s$lower, s$upper)
}
message("  simulating: baseline without priorities")
fcfs <- modifyList(baseline, list(name = "Baseline, no priorities", priorities = FALSE))
fcfs_envs <- run_scenario(fcfs)
priority_check <- data.frame(
  model = c("Simulation, priorities (as modeled)", "Simulation, first come first served",
            "M/G/c analytic check (no priorities)"),
  wait = c(tier1_wait(alerts[[1]]),
           tier1_wait(alert_table(get_mon_arrivals(fcfs_envs, ongoing = TRUE),
                                  get_mon_attributes(fcfs_envs), fcfs)),
           sprintf("%.2f", analytic$tier1_mean_wait_min[1]))
)
names(priority_check) <- c("baseline", "mean wait to triage, all severities (min, 95% CI)")

# ---- Figure 1: scenario comparison -----------------------------------------------
# The metrics that differ between scenarios at the baseline load; SLA breaches and missed
# incidents are near zero here and are shown in the stress test instead.
plot_metrics <- c(investigation_wait = "Wait for tier-2, confirmed incident (min)",
                  wait_high = "Wait to triage, high severity (min)",
                  util_tier1 = "Tier-1 utilization (%)",
                  util_tier2 = "Tier-2 utilization (%)")
fig_df <- summary_long[summary_long$metric %in% names(plot_metrics), ]
fig_df$panel <- factor(plot_metrics[fig_df$metric], levels = plot_metrics)
pct_panel <- fig_df$metric %in% c("util_tier1", "util_tier2")
fig_df[pct_panel, c("mean", "lower", "upper")] <- 100 * fig_df[pct_panel, c("mean", "lower", "upper")]
fig_df$scenario <- factor(fig_df$scenario, levels = rev(names(sim_results)))
p_cmp <- ggplot(fig_df, aes(mean, scenario)) +
  geom_col(fill = "#2b6cb0", width = 0.6) +
  geom_errorbar(aes(xmin = lower, xmax = upper), width = 0.25, colour = "grey25",
                orientation = "y") +
  facet_wrap(~panel, scales = "free_x", ncol = 2) +
  labs(title = "Staffing and process scenarios",
       subtitle = sprintf("Mean of %d replications x %d days, 95%% CI.",
                          SIM$replications, SIM$days),
       x = NULL, y = NULL) +
  theme_minimal(base_size = 11)
save_plot(p_cmp, "scenario_comparison.png", 10, 6)

# ---- Figure 2: triage wait distribution by severity (baseline) ------------------
base <- alerts[[1]]
p_wait <- ggplot(base[base$triaged, ], aes(pmax(triage_wait, 0.1), fill = severity)) +
  geom_histogram(bins = 60, alpha = 0.8, position = "identity") +
  geom_vline(data = data.frame(severity = factor(names(baseline$triage_sla),
                                                 levels = c("high", "medium", "low")),
                               sla = baseline$triage_sla),
             aes(xintercept = sla), linetype = 2) +
  facet_wrap(~severity, ncol = 1, scales = "free_y") +
  scale_x_log10() +
  scale_fill_manual(values = c(high = "#c53030", medium = "#dd6b20", low = "#718096"), guide = "none") +
  labs(title = "Baseline: wait from alert to start of triage",
       subtitle = "Dashed line = SLA. Log scale; waits under 0.1 min shown at 0.1.",
       x = "Minutes", y = "Alerts") +
  theme_minimal(base_size = 11)
save_plot(p_wait, "baseline_triage_wait.png", 8, 6)

# ---- Figure 3: tier-1 backlog over time, one baseline replication ---------------
res1 <- sim_results[[1]]$resources
res1 <- res1[res1$replication == 1 & res1$resource == "tier1", ]
p_q <- ggplot(res1, aes(time / 60 / 24, queue)) +
  geom_step(colour = "#2b6cb0") +
  geom_hline(yintercept = baseline$balk_queue_length, linetype = 2, colour = "#c53030") +
  annotate("text", x = 0.05, y = baseline$balk_queue_length + 0.8, hjust = 0, size = 3.2,
           label = "Low-severity alerts auto-closed above this backlog", colour = "#c53030") +
  labs(title = sprintf("Tier-1 backlog over %d simulated days (baseline, replication 1)", SIM$days),
       x = "Day", y = "Alerts waiting") +
  theme_minimal(base_size = 11)
save_plot(p_q, "tier1_backlog.png", 9, 3.8)

outcome_tbl <- as.data.frame.matrix(table(base$severity, base$outcome))
outcome_tbl <- cbind(severity = rownames(outcome_tbl), outcome_tbl)

report_add("## 1. Scenario comparison\n\n",
           sprintf("%d replications x %d days per scenario (first day discarded as warm-up). ",
                   SIM$replications, SIM$days),
           "Cells: mean (95% CI across replications).\n\n",
           paste(md_table(cmp), collapse = "\n"), "\n\n",
           "Replication *i* sees the same alerts in every scenario, so differences can be measured ",
           "replication by replication:\n\n",
           paste(md_table(paired), collapse = "\n"), "\n\n",
           "Tier-1 wait against the analytic check. Priority goes to high-severity alerts, which take ",
           "the longest to triage; serving long jobs first raises the average wait:\n\n",
           paste(md_table(priority_check), collapse = "\n"), "\n\n",
           "![Scenario comparison](figures/scenario_comparison.png)\n\n",
           "## 2. Baseline detail\n\n",
           "Alert outcomes in the measurement window (all replications):\n\n",
           paste(md_table(outcome_tbl), collapse = "\n"), "\n\n",
           "![Triage wait](figures/baseline_triage_wait.png)\n\n",
           "![Backlog](figures/tier1_backlog.png)\n")
