# capacity_planning_percentile_report

**Difficulty:** very_hard
**Occupation:** Platform Engineer
**Industry:** Cloud Infrastructure / SaaS

## Task Description

A Platform Engineer must produce a Q4 capacity planning dashboard using statistical Graphite functions that most engineers rarely use. The report requires two distinct views of CPU utilization across the EC2 fleet:

1. **P95 CPU Utilization** — the 95th percentile across all instances (worst-case planning ceiling)
2. **CPU Variability** — standard deviation across instances (consistency/spread indicator)

## Why This Is Hard

1. `percentileOfSeries()` is an advanced Graphite aggregation function not in everyday use
2. The agent must use the wildcard `ec2_instance_*` pattern correctly
3. `stddevSeries()` is even less commonly known
4. Two separate graphs with exact titles must be created in one dashboard
5. The percentile value (95) must be numerically correct

## Scoring (100 pts, pass ≥ 60)

| Criterion | Points |
|-----------|--------|
| Dashboard "Capacity Planning Q4" exists | 15 |
| Dashboard has ≥ 2 graphs | 10 |
| Graph "P95 CPU Utilization" found | 15 |
| percentileOfSeries with ec2_instance wildcard | 20 |
| Percentile value is 95 | 10 |
| Graph "CPU Variability" found | 15 |
| stddevSeries with ec2_instance wildcard | 15 |

## Verification

SQLite dashboard read → JSON export → verifier checks `target` arrays for `percentileOfSeries` and `stddevSeries` function calls with correct arguments.
