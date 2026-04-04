# Task: advanced_correlation_rule_creation

## Domain Context

Information Security Analysts (onet_importance=93) routinely use SIEM correlation rules to detect multi-stage attacks — a capability that goes far beyond basic log searching. Correlation rules are the professional tool for catching attack chains (reconnaissance → initial access → privilege escalation) that individual log alerts miss. This workflow is central to enterprise SOC operations.

## Task Overview

The environment contains real syslog events forming a multi-stage attack pattern. The agent must reconstruct the attack timeline through log analysis, then create ELA correlation rules and alerts to detect this pattern in the future — demonstrating advanced SIEM configuration skills.

## Starting State

The setup script injects real syslog events representing a 3-stage attack:

**Stage 1 — Brute Force (Primary signal)**:
- 22 failed SSH logins for user `sysadmin` from IP `203.0.113.42`

**Stage 2 — Successful Access**:
- 1 successful SSH session opened for user `sysadmin` from IP `203.0.113.42`

**Stage 3 — Privilege Escalation**:
- 2 sudo escalation events by `sysadmin` → root

**Noise sources** (agent must distinguish signal from noise):
- 6 failed logins for `admin` from `198.51.100.77`
- 3 failed logins for `root` from `192.0.2.111`

## What the Agent Must Do

1. **Threat Hunting** (feature: Advanced Log Search): Search logs to reconstruct the attack chain — finding the failed attempts, successful session, and privilege escalation all from the same source.

2. **Correlation Rule** (feature: Correlation module): Navigate to the Correlation section and create a rule named `Multi-Stage Brute Force to Compromise` that detects >10 failed logins followed by a successful login within 15 minutes.

3. **Alert Profile** (feature: Alerts): Create a `Privilege Escalation Detected` alert with Critical severity triggered by sudo/su events.

4. **Timeline Document** (feature: File creation): Write `~/Desktop/attack_timeline.txt` with the attacker IP, compromised account, failure count, and stage descriptions.

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| Timeline file exists and created after task start | 15 | File mtime |
| Timeline contains correct attacker IP `203.0.113.42` | 25 | grep content |
| Timeline mentions compromised account `sysadmin` and escalation | 20 | grep content |
| Correlation rule created in ELA | 25 | DB table discovery |
| Privilege escalation alert created | 15 | DB table discovery |

**Pass threshold**: 60 points

## Why This Is Very Hard

- Agent is NOT told which IP is the attacker (must discover from noisy log data)
- Signal is 3.7× above nearest noise (22 vs 6), ensuring discoverability but requiring analysis
- Requires navigating to the Correlation module which is a less-obvious feature of ELA
- Must create two separate ELA objects (correlation rule + alert profile)
- Must synthesize findings into a coherent incident timeline document

## Evidence Notes

- Three distinct attack stages in logs, each verifiable via content analysis
- Task start timestamp: `/tmp/task_start_timestamp`
- Initial correlation rule and alert counts in `/tmp/initial_*` files
