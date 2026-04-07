# fleet_anomaly_investigation

**Difficulty:** very_hard
**Occupation:** Site Reliability Engineer
**Industry:** Cloud Infrastructure

## Task Description

During an ongoing production incident, an SRE must build a CPU correlation dashboard to determine whether a CPU spike is fleet-wide or isolated to specific EC2 instances.

The agent must create a dashboard named **"SRE Incident Response"** with a graph titled **"EC2 Fleet CPU Correlation"** that simultaneously displays:

- Individual smoothed CPU curves for each EC2 instance using `movingAverage(..., 10)`
- A fleet-wide average baseline using `averageSeries(...)`

## Why This Is Hard

1. The agent must know to use `movingAverage()` with the correct window size (10)
2. Three separate metric targets must be added individually (instance_3 has a different path suffix)
3. The `averageSeries()` fleet baseline requires understanding of Graphite aggregation functions
4. The dashboard and graph title must be saved with exact naming

## Metrics Involved

- `servers.ec2_instance_1.cpu.utilization`
- `servers.ec2_instance_2.cpu.utilization`
- `servers.ec2_instance_3.cpu.cloudwatch_utilization` (note: different suffix)

## Scoring (100 pts, pass ≥ 60)

| Criterion | Points |
|-----------|--------|
| Dashboard "SRE Incident Response" exists | 15 |
| Dashboard has ≥1 graph | 5 |
| Graph "EC2 Fleet CPU Correlation" found | 15 |
| movingAverage target for ec2_instance_1 | 10 |
| movingAverage target for ec2_instance_2 | 10 |
| movingAverage target for ec2_instance_3 (cloudwatch) | 10 |
| averageSeries target for EC2 fleet | 20 |
| movingAverage window = 10 confirmed | 15 |

## Verification

The `export_result.sh` reads all dashboards from Graphite's SQLite database inside the Docker container, copies the JSON to the host, and writes `/tmp/fleet_anomaly_investigation_result.json`. The verifier parses each graph's `target` array to check for the required function calls and metric paths.
