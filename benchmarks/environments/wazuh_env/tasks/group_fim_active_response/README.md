# Task: group_fim_active_response

## Domain Context

**Primary users**: Information Security Engineers, Security Architects
**Real workflow**: Healthcare organizations implementing HIPAA technical safeguards for ePHI protection

Configuring File Integrity Monitoring (FIM) across server tiers is a standard security architecture activity. Security architects routinely create agent groups with differentiated monitoring profiles and automated response capabilities to meet compliance frameworks (HIPAA, PCI DSS, SOC 2).

## Task Overview

Configure Wazuh with a dedicated `critical-servers` agent group that has enhanced File Integrity Monitoring on sensitive system files, assign the Wazuh manager itself (agent 000) to this group, create a detection rule for critical file changes, and configure automated active response.

## Goal / End State

1. Agent group `critical-servers` exists in Wazuh
2. Agent 000 (Wazuh manager) is assigned to the `critical-servers` group
3. The group's `agent.conf` has syscheck (FIM) configured for: `/etc/passwd`, `/etc/shadow`, `/etc/ssh/`, `/etc/audit/`, `/var/log/auth.log` with real-time monitoring enabled
4. A custom rule in `local_rules.xml` fires at level >= 12 when a syscheck FIM event occurs on the monitored critical files
5. An active response entry in `ossec.conf` fires when the detection rule triggers

## Difficulty: very_hard

The agent must figure out:
- How to create an agent group via the Wazuh dashboard
- How to edit the group's `agent.conf` to add `<syscheck>` FIM configuration (not the global ossec.conf)
- How to assign agent 000 to a group (special handling for the manager agent)
- What the FIM parent rule SIDs are in Wazuh (550-556 range) to write a rule that fires on FIM events
- How to configure `<active-response>` in ossec.conf with appropriate `<command>` and `<rules_id>` entries

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| Group 'critical-servers' exists | 20 | Wazuh API GET /groups |
| Agent 000 in 'critical-servers' group | 20 | Wazuh API GET /agents/000?select=group |
| Group agent.conf has FIM for critical paths | 25 | XML parse /var/ossec/etc/shared/critical-servers/agent.conf |
| Custom FIM rule with level >= 10 | 20 | XML parse local_rules.xml for rules referencing FIM SIDs (550-556) |
| Active response in ossec.conf | 15 | grep ossec.conf for <active-response> |

**Pass threshold**: 70 points

## Key Wazuh Concepts

### Group Agent Config (FIM Configuration)
Located at: `/var/ossec/etc/shared/critical-servers/agent.conf`

```xml
<agent_config>
  <syscheck>
    <disabled>no</disabled>
    <frequency>300</frequency>
    <directories realtime="yes" check_all="yes">/etc/passwd,/etc/shadow,/etc/ssh/,/etc/audit/</directories>
    <directories realtime="yes" check_all="yes">/var/log/auth.log</directories>
  </syscheck>
</agent_config>
```

### FIM Parent Rule SIDs
- 550: Integrity checksum changed
- 551: File integrity monitoring
- 553: File modified
- 554: File added
- 555: File deleted

### Custom Rule for Critical File Modifications
```xml
<rule id="100050" level="12">
  <if_sid>553</if_sid>
  <description>Critical file modification detected - HIPAA ePHI integrity breach</description>
  <group>syscheck,fim,hipaa,</group>
</rule>
```

### Active Response
```xml
<active-response>
  <command>host-deny</command>
  <location>local</location>
  <rules_id>100050</rules_id>
  <timeout>600</timeout>
</active-response>
```

## Edge Cases

- Agent 000 is the manager itself — assigning it to a group requires the same API call as other agents
- The FIM configuration in `agent.conf` (group-level) overrides the global `ossec.conf` syscheck config for that group
- Real-time FIM requires `realtime="yes"` in the `<directories>` element
- After assigning agent 000 to the group and uploading `agent.conf`, a brief delay may be needed before the config is applied
