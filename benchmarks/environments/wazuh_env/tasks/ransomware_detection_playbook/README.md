# Task: Ransomware Detection Playbook

## Overview

**Difficulty**: Very Hard
**Timeout**: 600 seconds | **Max Steps**: 90
**Primary Occupation**: Information Security Engineer / SOC Analyst

This task simulates a realistic Security Operations Center (SOC) scenario where early-stage ransomware indicators have been detected across the network. The engineer must build a complete ransomware detection and automated response capability in Wazuh, chaining multiple independent features.

## Domain Context

Ransomware attacks typically follow a multi-stage kill chain:
- **T1490** – Inhibit System Recovery (shadow copy deletion: `vssadmin delete shadows`)
- **T1486** – Data Encrypted for Impact (mass file modification, encrypted extensions)
- **T1021** – Remote Services (lateral movement via SSH/SMB for spread)

Professional SOC engineers implement detection coverage for each stage, with correlation to detect the pattern across events and automated response to contain the threat.

## Starting State

The environment has pre-seeded ransomware-precursor log events in Wazuh:
- Shadow copy deletion commands in the audit log
- Mass file modification events with suspicious extensions (`.encrypted`, `.locked`, `.crypto`)
- Lateral movement events (SSH login from internal IPs)
- These appear in the Wazuh Alerts module but have no specific detection rules

## Goal (End State)

All of the following must be configured in Wazuh when done:

1. **File Integrity Monitoring** on ≥3 critical paths (e.g., `/home`, `/etc`, `/var/www`, `/var/backup`, `/opt`)
2. **Ransomware detection rule** (level ≥10) matching indicators like shadow copy deletion, encrypted file extensions, or mass modification commands
3. **Frequency correlation rule** using `frequency` and `timeframe` attributes — fires when ransomware-related events repeat within a time window
4. **Active response** block in `ossec.conf` that responds to critical ransomware detections
5. **Incident response playbook** at `/home/ga/Desktop/ransomware_playbook.txt` (≥600 characters)

## Scoring (100 points total)

| Criterion | Points |
|-----------|--------|
| FIM on ≥3 critical filesystem paths | 20 |
| Ransomware detection rule (level ≥10) | 25 |
| Correlation rule with frequency + timeframe | 25 |
| Active response configured in ossec.conf | 15 |
| Playbook document ≥600 chars, created after task start | 15 |

**Pass threshold**: 65 points
**Score cap**: If playbook is missing and score ≥65, score is capped at 64 (playbook is a required deliverable)

## Key Wazuh Concepts

### File Integrity Monitoring (FIM / Syscheck)
Configure in `ossec.conf` inside the `<syscheck>` block:
```xml
<syscheck>
  <directories realtime="yes">/etc,/home</directories>
  <directories realtime="yes">/var/www</directories>
</syscheck>
```

### Detection Rule Pattern (Ransomware Indicators)
```xml
<rule id="100050" level="12">
  <if_sid>0</if_sid>
  <match>vssadmin delete shadows|Delete Shadow|shadow copy</match>
  <description>Ransomware indicator: Shadow copy deletion attempt (T1490)</description>
  <mitre><id>T1490</id></mitre>
</rule>
```

### Frequency Correlation Rule
```xml
<rule id="100055" level="13" frequency="10" timeframe="120">
  <if_matched_sid>100050</if_matched_sid>
  <description>Ransomware: Mass shadow copy deletion - multiple events in 2 minutes</description>
  <same_source_ip />
</rule>
```

### Active Response in ossec.conf
```xml
<active-response>
  <command>host-deny</command>
  <location>local</location>
  <rules_id>100055</rules_id>
  <timeout>600</timeout>
</active-response>
```

## Files Modified by This Task

- `/var/ossec/etc/ossec.conf` — FIM and active-response configuration
- `/var/ossec/etc/rules/local_rules.xml` — Detection and correlation rules
- `/home/ga/Desktop/ransomware_playbook.txt` — Incident response playbook

## Verification Schema

The export script produces `/tmp/ransomware_detection_playbook_result.json`:
```json
{
  "task_start": 1700000000,
  "fim_path_count": 3,
  "ransomware_rule_found": 1,
  "ransomware_rule_level": 12,
  "correlation_found": 1,
  "correlation_frequency": 10,
  "ar_configured": 1,
  "playbook_exists": 1,
  "playbook_size": 850,
  "playbook_after_start": 1
}
```
