# Changelog: from the 2022 original to this release

## Rebuild for publication (2026)

**Reframed** the original 2022 queueing models (call centers and a clinic) as a two-tier SOC. The original problem materials are not redistributed; the model was rewritten from scratch.

| Technique from the study | Where it lives now |
|---|---|
| `branch()` on a random type with different service distributions | Severity branch with triangular triage times |
| `set_prioritization()` high/low patients | High / medium / low alert priority in both tiers |
| `leave()` balking when the queue is long | Low-severity alerts auto-closed when the tier-1 backlog reaches 15 |
| `renege_in()` / `renege_abort()` | Low-severity alerts expire if not picked up within U(60, 120) min |
| Two-stage service (nurse → doctor) | Tier-1 triage → tier-2 investigation for real incidents |
| 50 replications with `lapply` | 100 replications per scenario, common random numbers, 95% CIs |

**Improvements**
- Balking and reneging are recorded explicitly as attributes, rather than inferred from arrivals still in the system at the end of a run.
- Trajectories are built per replication, so each run is independent.
- Base-R triangular sampler and ggplot2 figures (fewer dependencies).
- Added warm-up and cool-down windows, censoring-aware SLA metrics, an analytic M/G/c cross-check, metric tests, `run_all.R` and the generated report.
- Stress-test figure leads the README; the scenario figure now shows the metrics that differ at baseline load (tier-2 wait, high-severity wait, utilization).
- Explained why the simulated tier-1 wait is above the M/G/c estimate (priority to the longest jobs), and that an extra tier-1 analyst raises tier-2 waits.
- Corrected the seeds note: shared seeds per replication, not common random numbers.
- Parameter validation before every run, with tests; no automatic package installs; CI lower bounds clipped at zero.
- Daily alert cycle (non-homogeneous Poisson arrivals), shift schedules and an alert-flood scenario with a planted real alert (`scripts/04_daily_cycle.R`).
- Common random numbers: every alert's random inputs are drawn before the run, so staffing options see the same alerts; paired differences against the baseline. Detection tuning now removes false positives from the same alert stream.
- Queues drain after the last arrival, so tier-2 waits are no longer censored (the old cool-down window is gone); utilization is measured over the measurement window, with shift capacity.
- P90 waits; stress-test breaking points at 95% confidence as well as on the mean; the no-priority check against the analytic tier-1 wait is generated in the report.
- `testthat` suite with model tests, `renv.lock`, and CI (tests, pipeline, results check, R 4.1, gitleaks).

**Not included**
- Third-party problem statements and materials from the original program.

## Original work (2022)
- Graduate study in Simulation & Optimization, Texas Tech University: discrete-event simulation with simmer
