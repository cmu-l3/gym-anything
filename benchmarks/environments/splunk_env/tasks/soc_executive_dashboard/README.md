# Task: soc_executive_dashboard

## Overview

**Role**: Security Operations Manager / CISO Support
**Difficulty**: very_hard
**Domain**: Security Operations — Executive Dashboard + Alerting

Security managers use Splunk to create executive dashboards for board-level reporting and to configure volume-based alerting for high-priority threat scenarios. This task combines dashboard construction (with multiple panels, each requiring different SPL queries) with alert configuration — a complex multi-feature Splunk task.

## Goal

Build a comprehensive SOC executive dashboard and a companion high-volume attack alert:

1. Dashboard **`SOC_Executive_Dashboard`** with at least **3 panels** covering:
   - Failed authentication trends over time
   - Top attacking source IPs by attempt count
   - Most frequently targeted user accounts

2. Alert **`High_Volume_Attack_Alert`** that:
   - Detects when any single source IP has >50 failed logins within 1 hour
   - Is scheduled to run every 30 minutes (`*/30 * * * *`)

Both must draw from the `security_logs` index.

## What the End State Looks Like

- New dashboard `SOC_Executive_Dashboard` exists with ≥3 panels
- Dashboard panel searches reference `security_logs`
- New saved alert `High_Volume_Attack_Alert` exists
- Alert is scheduled at `*/30 * * * *`
- Alert search includes a threshold condition (count > 50 or similar)

## Verification Strategy

| Criterion | Score | Description |
|-----------|-------|-------------|
| Dashboard created | 20% | New dashboard "SOC_Executive_Dashboard" exists |
| Dashboard has ≥3 panels | 20% | Dashboard XML contains ≥3 `<panel>` elements |
| Dashboard refs security_logs | 20% | Dashboard panel searches reference security_logs index |
| Alert created and scheduled | 20% | Alert "High_Volume_Attack_Alert" exists, scheduled every 30 min |
| Alert has threshold | 20% | Alert search contains a numeric count threshold |

Score ≥ 60% = passed.

## Key Data Available

The `security_logs` index has:
- SSH failed password events (large volume, many source IPs)
- SSH successful login events
- Multiple target usernames (root, admin, oracle, etc.)

## Schema Reference

Panel count in dashboard XML:
```python
import re
panel_count = len(re.findall(r'<panel\b', dashboard_xml, re.IGNORECASE))
```

Dashboard REST endpoint:
```
GET https://localhost:8089/servicesNS/-/-/data/ui/views/SOC_Executive_Dashboard?output_mode=json
```

The XML is in `content["eai:data"]`.

Example panel structure:
```xml
<dashboard>
  <row>
    <panel>
      <chart>
        <search><query>index=security_logs "Failed password" | timechart span=1h count</query></search>
        <option name="charting.chart">line</option>
      </chart>
      <title>Failed Auth Trend</title>
    </panel>
  </row>
</dashboard>
```
