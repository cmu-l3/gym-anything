# dual_axis_resource_correlation (`dual_axis_resource_correlation@1`)

## Overview

This task evaluates the agent's ability to create a production-quality dual-axis monitoring graph in Graphite that correlates two metrics with different scales (CPU percentage vs disk bytes) on a single chart using `alias()` for human-readable legends and `secondYAxis()` to render a second metric on the right Y-axis.

## Rationale

**Why this task is valuable:**
- Tests knowledge of Graphite's presentation-layer functions (`alias()`, `secondYAxis()`)
- Requires combining two metrics with fundamentally different units on one graph
- Evaluates the agent's ability to create operationally useful dashboards, not just data dumps
- Dual-axis charts are a universal monitoring pattern for resource correlation analysis

**Real-world Context:** A junior systems administrator at a managed services provider has been asked by their team lead to create a correlation dashboard for a client's EC2 instance. The client is experiencing intermittent slowdowns and the team suspects a relationship between CPU spikes and disk I/O bursts. The admin needs a single graph showing both metrics with readable legends so the on-call team can quickly assess whether performance issues are CPU-bound or I/O-bound.

## Task Description

**Goal:** Create a Graphite dashboard named **"Resource Correlation"** containing a single dual-axis graph that displays CPU utilization on the left Y-axis and disk write bytes on the right Y-axis for EC2 Instance 1, with human-readable legend aliases.

**Starting State:** Firefox is open to the Graphite web UI at `http://localhost/`. Real NAB time-series data has been loaded, including EC2 CPU utilization and disk write metrics. No dashboards have been created.

**Expected Actions:**
1. Navigate to the Graphite Dashboard interface
2. Create a new dashboard named **"Resource Correlation"**
3. Add a graph titled **"CPU vs Disk Activity"**
4. Add the CPU metric `servers.ec2_instance_1.cpu.utilization` wrapped with `alias()` to display as **"CPU Utilization %"**
5. Add the disk metric `servers.ec2_instance_1.disk.write_bytes` wrapped with both `alias()` (displaying as **"Disk Write Bytes"**) and `secondYAxis()` to render on the right Y-axis
6. Save the dashboard

The resulting graph targets should be functionally equivalent to:
- `alias(servers.ec2_instance_1.cpu.utilization,"CPU Utilization %")`
- `secondYAxis(alias(servers.ec2_instance_1.disk.write_bytes,"Disk Write Bytes"))`

Note: The nesting order of `secondYAxis()` and `alias()` does not matter — `alias(secondYAxis(...), "...")` is equally valid.

**Final State:** A saved dashboard named "Resource Correlation" containing one graph with two targets using the specified functions and metric paths.

## Verification Strategy

### Primary Verification: Dashboard JSON Analysis

The verifier reads dashboards from Graphite's internal SQLite database (`/opt/graphite/storage/graphite.db` inside the Docker container) and exports the dashboard JSON. It then inspects each graph's `target` array for the required function calls and metric paths.

Checks performed:
- Dashboard name match (case-insensitive)
- Graph title match within the dashboard
- Metric path presence in targets
- Function wrapping (`alias()`, `secondYAxis()`) detected via string parsing
- Alias string values checked for expected legend names

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Dashboard "Resource Correlation" exists | 15 | Dashboard found in Graphite's SQLite database |
| Dashboard has ≥ 1 graph | 5 | At least one graph panel present |
| Graph titled "CPU vs Disk Activity" found | 15 | Exact graph title match (case-insensitive) |
| Target contains `ec2_instance_1.cpu.utilization` | 10 | CPU metric path present in any target |
| Target contains `ec2_instance_1.disk.write_bytes` | 10 | Disk metric path present in any target |
| `alias()` used on CPU metric with correct label | 10 | `alias(...)` wrapping CPU metric, legend contains "CPU Utilization" |
| `alias()` used on disk metric with correct label | 10 | `alias(...)` wrapping disk metric, legend contains "Disk Write" |
| `secondYAxis()` used on disk metric | 20 | `secondYAxis(...)` wrapping the disk write metric (not the CPU metric) |
| Both metrics in same graph | 5 | Correlation: both targets appear in one graph |
| **Total** | **100** | |

**Pass Threshold:** 60 points