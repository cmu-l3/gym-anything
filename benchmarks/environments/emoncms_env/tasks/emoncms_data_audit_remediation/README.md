# Task: emoncms_data_audit_remediation

## Overview

An energy data quality engineer has been asked to audit and remediate the Emoncms
configuration after a system migration introduced several silent failures. Data is
being received at the inputs but is either being silently discarded or stored
incorrectly due to broken process lists and invalid feed metadata.

## Domain Context

Building energy managers and data engineers who manage Emoncms deployments must
regularly audit that:
- Input process lists reference valid, existing feed IDs (broken IDs cause silent data loss)
- Feed storage intervals are valid (interval=0 disables writing)
- Feed engines are enabled (engine=0 disables storage entirely)

## Starting State (Injected Broken Configs)

The setup script deliberately injects 5 configuration errors:

1. **`power1` input** — processlist set to `1:99991` (non-existent feed ID; data silently dropped)
2. **`solar` input** — processlist set to `1:99992` (non-existent feed ID; data silently dropped)
3. **`House Power` feed** — `interval` set to `0` (invalid; PHPFina cannot write data)
4. **`House Temperature` feed** — `engine` set to `0` (disabled; no storage engine active)
5. **`Solar PV` feed** — `tag` cleared to empty string (feed is untagged/unclassifiable)

## Goal

Find and fix all 5 broken configurations:
1. Re-wire `power1` input processlist to reference the actual `House Power` feed ID
2. Re-wire `solar` input processlist to reference the actual `Solar PV` feed ID
3. Set `House Power` feed interval to a valid value (e.g. 10 seconds)
4. Set `House Temperature` feed engine to a valid value (e.g. 5 for PHPFina)
5. Set `Solar PV` feed tag to a non-empty value (e.g. "solar" or "power")

## Success Criteria

| Criterion | Points |
|-----------|--------|
| `power1` processlist references a valid (existing) feed ID | 20 |
| `solar` processlist references a valid (existing) feed ID | 20 |
| `House Power` feed has interval > 0 | 20 |
| `House Temperature` feed has engine > 0 | 20 |
| `Solar PV` feed has a non-empty tag | 20 |
| **Total** | **100** |
| **Pass threshold** | **≥60** |

## Verification

`export_result.sh` exports the current state of all 5 configurations.
`verifier.py` scores each criterion independently.

## Key Database Queries

```sql
-- Check input processlists
SELECT name, processList FROM input WHERE userid=1;

-- Check feed metadata
SELECT name, interval, engine, tag FROM feeds WHERE userid=1;

-- Find the real feed ID for a named feed
SELECT id FROM feeds WHERE name='House Power' AND userid=1;
```

## Credentials

- URL: http://localhost
- Username: admin
- Password: admin
