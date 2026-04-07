# metric_audit_clean_dashboard

**Difficulty:** very_hard
**Occupation:** Infrastructure Security Auditor
**Industry:** Cloud Infrastructure / FinTech

## Task Description

A contamination injection task. During setup, three fake metrics are injected into the Graphite Carbon pipeline:

- `servers.UNKNOWN_HOST.cpu.utilization` — clearly invalid hostname
- `servers.ec2_instance_99.cpu.utilization` — non-existent instance number
- `servers.test_node.machine_temperature` — wrong namespace/metric type

The agent must **browse the metric tree**, identify which metrics are legitimate, then create a dashboard **"Validated Production Metrics"** containing ONLY the three valid EC2 CPU metrics while excluding all contaminated ones.

## Why This Is Hard

1. The agent must actually explore the metric tree to identify contamination
2. Wildcards (`ec2_instance_*`) are forbidden — they capture contaminated metrics
3. The agent must make a security judgment about metric legitimacy
4. Three instances have different metric name suffixes (`utilization` vs `cloudwatch_utilization`)
5. `ec2_instance_99` looks plausibly real and is the hardest contaminant to catch

## Contamination Metrics (seeded by setup)

| Metric | Why It's Fake |
|--------|---------------|
| `servers.UNKNOWN_HOST.cpu.utilization` | Hostname is `UNKNOWN_HOST` |
| `servers.ec2_instance_99.cpu.utilization` | Instance 99 doesn't exist in production |
| `servers.test_node.machine_temperature` | Wrong host namespace, wrong metric type |

## Scoring (100 pts, pass ≥ 60)

| Criterion | Points |
|-----------|--------|
| Dashboard "Validated Production Metrics" exists | 10 |
| Dashboard has ≥ 1 graph | 5 |
| ec2_instance_1.cpu.utilization present in dashboard | 10 |
| ec2_instance_2.cpu.utilization present in dashboard | 10 |
| ec2_instance_3.cpu.cloudwatch_utilization present | 10 |
| No UNKNOWN_HOST metric (gated: requires all 3 valid) | 20 |
| No ec2_instance_99 metric (gated: requires all 3 valid) | 15 |
| No test_node metric (gated: requires all 3 valid) | 20 |

**Gating rule**: Absence criteria (the 55 pts) are only awarded if ALL 3 valid metrics are present. An empty dashboard trivially excludes contamination — the agent must both include the valid metrics AND exclude the contaminated ones.

## Verification

Verifier checks each graph's `target` list for presence of valid metrics and absence of contamination metric substrings. Wildcards that could expand to contaminated metrics are treated as potential contamination.
