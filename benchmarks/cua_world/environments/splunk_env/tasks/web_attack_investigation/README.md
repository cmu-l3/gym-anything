# Task: web_attack_investigation

## Overview

**Role**: Incident Responder / Information Security Engineer
**Difficulty**: very_hard
**Domain**: Incident Response — Multi-Vector Attack Correlation

A core incident response workflow involves correlating attack activity across multiple log sources to identify whether isolated alerts represent a coordinated campaign. This task requires the agent to investigate independently across two indexes, correlate findings, and build both a reusable detection report and an operational dashboard.

## Goal

Investigate available Splunk data to find evidence of coordinated attack activity that appears in both web access logs and SSH authentication logs. Create:

1. A saved report named **`Multi_Vector_Attack_Report`** that correlates attack activity across web and security log sources to surface common threat actor IPs
2. A dashboard named **`Threat_Intelligence_Dashboard`** with at least 2 panels visualizing attack patterns

## What the End State Looks Like

- A new saved search named `Multi_Vector_Attack_Report` exists
- The search queries data from both `web_logs` and `security_logs` (or uses index=* with filtering)
- A new dashboard named `Threat_Intelligence_Dashboard` exists in Splunk
- The dashboard contains at least 2 visualization panels

## Verification Strategy

| Criterion | Score | Description |
|-----------|-------|-------------|
| Report created | 20% | New saved search "Multi_Vector_Attack_Report" exists |
| Report cross-index | 20% | Search references both web and security log data |
| Dashboard created | 20% | New dashboard "Threat_Intelligence_Dashboard" exists |
| Dashboard has panels | 20% | Dashboard XML contains ≥2 panel elements |
| Dashboard references logs | 20% | Dashboard panel searches reference security or web log indexes |

Score ≥ 60% = passed.

## Key Data Available

- `web_logs` index: Apache error logs (real Loghub data) with client IPs and error types
- `security_logs` index: SSH authentication logs with source IPs

## Investigation Approach (for Task Designer Reference Only)

The agent needs to discover independently:
1. What fields/patterns exist in web_logs (Apache error format)
2. What fields/patterns exist in security_logs (SSH auth format)
3. How to correlate IP addresses across both

Common SPL approaches an expert would use:
```spl
# Find IPs in both indexes using subsearch
index=security_logs "Failed password"
  [search index=web_logs | rex field=_raw "(?:client|from)\s+(?P<src_ip>\d+\.\d+\.\d+\.\d+)" | stats count by src_ip | fields src_ip]
| stats count by src_ip
```

Or using union/append:
```spl
index=web_logs OR index=security_logs
| rex field=_raw "(\d{1,3}\.){3}\d{1,3}"
| stats count by index, src_ip
```

## Schema Reference

Dashboard XML endpoint:
```
GET https://localhost:8089/servicesNS/-/-/data/ui/views/Threat_Intelligence_Dashboard?output_mode=json
```
The dashboard XML is in `content["eai:data"]`. Count `<panel>` tags to verify panel count.
