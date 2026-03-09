# Task: incident_correlation_response

## Domain Context

**Primary users**: Information Security Engineers, Information Security Analysts
**GDP footprint**: Combined $3.4B (top two occupational segments)
**Real workflows**:
- "Essential for log aggregation, threat detection, and incident response monitoring across the enterprise" (Engineers)
- "SIEM platforms are the primary dashboard for security analysts to monitor, detect, and respond to incidents" (Analysts)

Correlation rule creation and incident documentation are daily activities for detection engineers. Translating observed attack patterns into frequency-based correlation rules that escalate severity represents sophisticated SOC engineering work.

## Task Overview

Investigate real security events in the Wazuh dashboard, create a frequency/timeframe-based correlation rule that escalates repeated occurrences into high-severity alerts, configure active response, and write an incident investigation report.

## Goal / End State

1. A custom rule in `local_rules.xml` uses `frequency` and `timeframe` attributes (Wazuh composite rule syntax) to detect repeated occurrences of the same event type, at severity level >= 13
2. An active response entry in `ossec.conf` fires when the correlation rule triggers
3. An incident report exists at `/home/ga/Desktop/incident_report.txt` created after task start, with >= 300 characters
4. (Report should document the investigated events, correlation pattern chosen, frequency/timeframe thresholds, and response actions configured)

## Difficulty: very_hard

The agent must figure out:
- How to navigate the Wazuh dashboard to find and analyze current alerts (Events, Security Events, Overview sections)
- Which specific rule IDs are frequently firing in the current environment (requires investigation)
- Wazuh's frequency/timeframe composite rule syntax — a non-obvious feature requiring documentation knowledge
- How the `<if_matched_sid>` element references the parent rule being correlated
- How to configure `<active-response>` in ossec.conf with command, location, and rule reference
- What constitutes a meaningful incident report for the detected pattern

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| Correlation rule with `frequency` + `timeframe` attributes | 30 | XML parse local_rules.xml for rules with both attributes |
| +10 bonus if rule level >= 13 | +10 bonus | Check level attribute |
| Active response in ossec.conf | 25 | grep ossec.conf for <active-response> (new or modified) |
| Incident report at Desktop/incident_report.txt | 20 | File existence check |
| Report created after task start | 15 | stat mtime vs task_start_timestamp |
| Report >= 300 characters | 10 | wc -c |

**Pass threshold**: 65 points
**Score cap**: Report is a required deliverable — score capped at 64 if missing

## Real Data Context

The setup script generates real SSH authentication failure events by attempting SSH connections with an invalid username. Wazuh captures these as genuine system events and fires existing rules (e.g., rule 5710: SSH invalid user). The agent should investigate these real alerts and create a correlation rule that fires when the same pattern recurs multiple times within a time window.

## Wazuh Correlation Rule Syntax

Frequency/timeframe composite rules require both `frequency` and `timeframe` attributes on the `<rule>` element, plus an `<if_matched_sid>` child to specify which parent rule is being correlated:

```xml
<rule id="100200" level="13" frequency="5" timeframe="180">
  <if_matched_sid>5710</if_matched_sid>
  <same_source_ip/>
  <description>Multiple SSH invalid user attempts from same source - credential stuffing attack (5 in 3 min)</description>
  <group>authentication_failures,brute_force,mitre_att&amp;ck,</group>
  <mitre>
    <id>T1110</id>
  </mitre>
</rule>
```

**Key attributes:**
- `frequency`: How many matches of the parent rule must occur
- `timeframe`: Time window in seconds within which the matches must occur
- `<if_matched_sid>`: The parent rule ID to correlate
- `<same_source_ip/>`: Optional — require all occurrences from the same source

## Active Response Example

```xml
<active-response>
  <command>firewall-drop</command>
  <location>local</location>
  <rules_id>100200</rules_id>
  <timeout>3600</timeout>
</active-response>
```

## Wazuh API — Finding Top Firing Rules

```bash
# Get recent alerts via API
TOKEN=$(curl -sk -u wazuh-wui:'MyS3cr37P450r.*-' -X POST \
  'https://localhost:55000/security/user/authenticate?raw=true')

curl -sk "https://localhost:55000/security/events?limit=20" \
  -H "Authorization: Bearer $TOKEN"
```

## Edge Cases

- The `frequency` and `timeframe` attributes are at the rule level, NOT inside child elements
- `<if_matched_sid>` must reference an existing built-in Wazuh rule ID (use one that's actively firing)
- After saving the rule, Wazuh needs to process a new event to test the correlation (the manager restarts automatically after rule changes via dashboard)
- The incident report can be created with any text editor (gedit, nano, or redirect in terminal)
