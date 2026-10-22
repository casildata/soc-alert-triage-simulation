# Analytic sanity check (base R, no simmer needed).
# Treats each tier as an M/G/c queue and uses the Allen-Cunneen approximation
#   Wq ≈ ErlangC_Wq(M/M/c) × (Ca² + Cs²) / 2
# It ignores priorities, auto-closing and expiry, so it is a ballpark for the average
# tier-1 wait and a check that every scenario is stable (utilization < 1). The simulated
# tier-1 wait comes in higher because priority goes to high-severity alerts, which take the
# longest to triage, and serving long jobs first raises the average wait.

erlang_c_wait <- function(lambda, mean_service, c) {
  a <- lambda * mean_service           # offered load (Erlangs)
  rho <- a / c
  if (rho >= 1) return(c(rho = rho, p_wait = 1, wq = Inf))
  k <- 0:(c - 1)
  top <- a^c / factorial(c) / (1 - rho)
  p_wait <- top / (sum(a^k / factorial(k)) + top)
  c(rho = rho, p_wait = p_wait, wq = p_wait * mean_service / (c - a))
}

tri_moments <- function(t) {
  a <- t[1]; m <- t[2]; b <- t[3]
  mu <- (a + m + b) / 3
  v <- (a^2 + m^2 + b^2 - a * m - a * b - m * b) / 18
  c(mean = mu, second = v + mu^2)
}

check_scenario <- function(p) {
  lambda <- p$alerts_per_hour / 60                                   # per minute
  mix <- p$severity_mix[c("high", "medium", "low")]
  mom <- sapply(p$triage_time[c("high", "medium", "low")], tri_moments)
  es <- sum(mix * mom["mean", ]); es2 <- sum(mix * mom["second", ])
  cs2_t1 <- (es2 - es^2) / es^2                                      # mixture SCV
  t1 <- erlang_c_wait(lambda, es, p$tier1_analysts)
  lambda2 <- lambda * sum(mix * p$true_positive_rate[c("high", "medium", "low")])
  t2 <- erlang_c_wait(lambda2, p$investigation_mean, p$tier2_analysts)
  cs2_t2 <- 1 / p$investigation_shape                                # gamma SCV
  data.frame(scenario = p$name,
             tier1_utilization = unname(t1["rho"]),
             tier1_mean_wait_min = unname(t1["wq"] * (1 + cs2_t1) / 2),
             tier2_utilization = unname(t2["rho"]),
             tier2_mean_wait_min = unname(t2["wq"] * (1 + cs2_t2) / 2),
             incidents_per_day = lambda2 * 60 * 24)
}

analytic <- do.call(rbind, lapply(SCENARIOS, check_scenario))
write.csv(analytic, "outputs/analytic_check.csv", row.names = FALSE)
print(analytic)
stopifnot(all(analytic$tier1_utilization < 1), all(analytic$tier2_utilization < 1))

fmt <- analytic
fmt[, -1] <- lapply(fmt[, -1], function(x) sprintf("%.2f", x))
report_add("## 0. Analytic check (M/G/c, Allen-Cunneen)\n\n",
           "Ignores priorities, auto-closing and expiry. Waits are in minutes.\n\n",
           paste(md_table(fmt), collapse = "\n"), "\n")
