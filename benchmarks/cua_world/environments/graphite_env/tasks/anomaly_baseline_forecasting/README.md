# anomaly_baseline_forecasting

**Difficulty:** very_hard
**Occupation:** Monitoring / ML Engineer
**Industry:** Cloud Infrastructure

## Task Description

A Monitoring Engineer implements Graphite's Holt-Winters triple exponential smoothing for automated anomaly detection. This requires using two advanced forecasting functions that most Graphite users have never touched.

Dashboard **"Anomaly Detection"**, graph **"Holt-Winters CPU Forecast"**, must contain:

1. `holtWintersForecast(servers.ec2_instance_2.cpu.utilization)` — the forecast baseline
2. `holtWintersConfidenceBands(servers.ec2_instance_2.cpu.utilization)` — the anomaly envelope

## Why This Is Hard

1. `holtWintersForecast()` and `holtWintersConfidenceBands()` are extremely rarely-used Graphite functions requiring domain knowledge of time-series forecasting
2. The agent must target `ec2_instance_2` specifically (not a wildcard, not instance 1 or 3)
3. Both functions are required simultaneously in one graph
4. Graphite requires sufficient historical data for Holt-Winters to work (the data must be loaded first)

## Scoring (100 pts, pass ≥ 60)

| Criterion | Points |
|-----------|--------|
| Dashboard "Anomaly Detection" exists | 15 |
| Dashboard has ≥ 1 graph | 5 |
| Graph "Holt-Winters CPU Forecast" found | 15 |
| holtWintersForecast(ec2_instance_2.cpu.utilization) present | 30 |
| holtWintersConfidenceBands(ec2_instance_2.cpu.utilization) present | 30 |
| Both forecast AND confidence bands present (completeness bonus) | 5 |

## Verification

The verifier checks each graph target for the Holt-Winters function names combined with `ec2_instance_2.cpu.utilization`. Using instance_1 or instance_3 does not satisfy the check.
