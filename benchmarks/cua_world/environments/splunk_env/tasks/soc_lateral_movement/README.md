# Task: soc_lateral_movement

## Overview

**Role**: SOC Analyst / Information Security Analyst
**Difficulty**: very_hard
**Domain**: Security Operations — Credential Compromise Detection

Security Analysts use Splunk as their primary SIEM dashboard. A core weekly workflow is investigating whether ongoing brute-force activity has resulted in actual account compromise — a pattern where an attacker systematically tries passwords and eventually succeeds. This task models that real investigation.

## Goal

Investigate the `security_logs` index to identify source IPs that exhibit credential stuffing success (both failed AND successful authentication events for the same user account). Build continuous monitoring by creating a saved alert named **`Compromised_Account_Detection`** that detects this pattern and runs on an hourly schedule.

The agent must:
1. Discover the authentication event structure in security_logs independently
2. Understand what fields/keywords distinguish failed vs. successful logins
3. Write a SPL query that correlates failure-then-success patterns from the same source
4. Save it as a scheduled alert with the exact name specified

## What the End State Looks Like

- A new saved search/alert named `Compromised_Account_Detection` exists in Splunk
- The search queries the `security_logs` index
- The search logic detects BOTH failed and successful login events (the query must contain both "Failed" or "fail" and "Accepted" or "success" keywords, or use a stats/transaction approach that captures both)
- The alert is scheduled (is_scheduled = 1) with a cron schedule indicating hourly execution (e.g., `0 * * * *` or `*/60 * * * *`)

## Verification Strategy

The verifier checks 5 independent criteria, each worth 20%:

| Criterion | Score | Description |
|-----------|-------|-------------|
| Alert exists | 20% | A new saved search named "Compromised_Account_Detection" was created |
| Correct name | 20% | Name matches exactly (case-insensitive, normalized) |
| References security_logs | 20% | Search contains `security_logs` index reference |
| Detects both fail + success | 20% | Search logic includes keywords/patterns for both failure and success states |
| Hourly schedule | 20% | Alert is scheduled with an hourly cron expression |

Score ≥ 60% = passed (at minimum 3 of 5 criteria must be met).

## Key Data in Environment

The `security_logs` index contains real SSH authentication logs (auth.log format):
- Failed authentication events: contain "Failed password"
- Successful authentication events: contain "Accepted password"
- Fields: source IP, username, timestamp, port

## Edge Cases

- The agent may attempt to use the REST API instead of the UI — both approaches produce the same Splunk artifacts and are equally valid
- The alert name must normalize to `compromised_account_detection` (underscores, case-insensitive)
- Hourly schedules may be expressed as `0 * * * *` or `*/60 * * * *` — both are accepted

## Schema Reference

```
index=security_logs
sourcetype=linux_secure
key fields in raw text: "Failed password", "Accepted password", src_ip (extracted), user
```

Splunk REST API for verification:
```
GET https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0
```
