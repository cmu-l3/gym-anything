# Task: syslog_volume_monitor

## Overview

**Role**: IT Operations Engineer / SRE
**Difficulty**: very_hard
**Domain**: Infrastructure Monitoring — Log Volume Anomaly Detection

Infrastructure engineers use Splunk to monitor system health by tracking log volume as a proxy for system activity. Unusual spikes or drops in log volume can signal security incidents, runaway processes, or monitoring gaps. This task models building a Splunk-based operational monitoring capability from scratch.

## Goal

Using the `system_logs` index, build Splunk monitoring infrastructure consisting of:

1. A saved report named **`System_Log_Volume_Report`** that analyzes system log volume over time (using time-based grouping) and is scheduled to run **daily**
2. A dashboard named **`Infrastructure_Health_Dashboard`** with at least **2 panels** showing log volume trends

## What the End State Looks Like

- New saved search `System_Log_Volume_Report` exists in Splunk
- The search queries `system_logs` index
- The search uses temporal analysis (timechart, stats count by time, or equivalent)
- The search is scheduled to run daily (cron like `0 0 * * *`)
- New dashboard `Infrastructure_Health_Dashboard` exists with ≥2 panels

## Verification Strategy

| Criterion | Score | Description |
|-----------|-------|-------------|
| Report created | 20% | New saved search "System_Log_Volume_Report" exists |
| References system_logs | 20% | Search queries system_logs index |
| Uses time analysis | 20% | Search uses timechart, stats count by _time, or similar temporal grouping |
| Scheduled daily | 20% | Alert is scheduled with daily cron (0 0 * * * or 0 * * * * etc.) |
| Dashboard with panels | 20% | Dashboard "Infrastructure_Health_Dashboard" exists with ≥2 panels |

Score ≥ 60% = passed.

## Key Data Available

- `system_logs` index contains real Linux syslog data (Loghub dataset) — kernel messages, daemon logs, cron activity
- Data spans multiple hours/days enabling meaningful time-series analysis

## Schema Reference

Typical SPL for this workflow:
```spl
index=system_logs | timechart span=1h count
```
Or with anomaly detection:
```spl
index=system_logs | timechart span=1h count | anomalydetection "count"
```

Dashboard and saved search REST endpoints:
```
GET https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json
GET https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json
```
