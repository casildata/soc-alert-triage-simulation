# Changelog: coursework → public repository

## Rebuild for publication (2026)

**Reframed** the ISQS 7339 Homework 3 queueing models as a two-tier SOC. Course
materials are not included; the model was rewritten from scratch.

| Homework technique | Where it lives now |
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

**Not included**
- Course-provided materials and the standalone homework problems.

## Original submission (Spring 2022)
- ISQS 7339 Homework 3: discrete-event simulation with simmer
