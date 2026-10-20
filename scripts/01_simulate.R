# Run every staffing / process scenario and keep only the monitor tables we need.

sim_results <- lapply(SCENARIOS, function(p) {
  message("  simulating: ", p$name, " (", SIM$replications, " replications x ", SIM$days, " days)")
  envs <- run_scenario(p)
  list(params = p,
       arrivals = get_mon_arrivals(envs, ongoing = TRUE),
       attributes = get_mon_attributes(envs),
       resources = get_mon_resources(envs))
})
names(sim_results) <- vapply(SCENARIOS, `[[`, "", "name")
saveRDS(sim_results, "outputs/sim_results.rds")
