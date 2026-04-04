# Task: solar_storage_monitoring_pipeline

## Overview

An energy systems engineer is commissioning a solar PV and battery energy storage
system (BESS). The BMS controller is live and posting four channels of data every 10
seconds to Emoncms under node `pvbms`, but no feeds or logging pipelines have been
configured yet. The engineer must set up the complete data pipeline from scratch.

## Domain Context

Energy systems engineers who install solar + storage systems use Emoncms (or similar
SCADA/monitoring platforms) to:
- Log instantaneous power and state-of-charge data to time-series feeds
- Accumulate energy (Wh/kWh) from power measurements using integration processes
- Build dashboards for facility managers to monitor solar yield and battery cycling

## Goal

Configure a fully operational solar + battery monitoring pipeline in Emoncms:

1. **Input process lists** — Each of the four `pvbms` inputs must have a process list
   configured to log data to a named feed:
   - `solar_w` → Log to Feed (named something like "Solar Generation") **AND**
     Power-to-kWh accumulation (a separate kWh feed, e.g. "Solar Energy kWh")
   - `battery_soc` → Log to Feed (named something like "Battery State of Charge")
   - `battery_charge_w` → Log to Feed (named something like "Battery Charge Power")
   - `battery_discharge_w` → Log to Feed (named something like "Battery Discharge Power")

2. **Feeds** — At least 5 feeds must exist for the pvbms/solar/battery monitoring
   (4 channels + the kWh accumulator for solar = 5 minimum).

3. **Dashboard** — A dashboard named **'Solar Storage Monitor'** must exist with
   at least 4 widgets showing the key metrics.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| `solar_w` has ≥2 process steps (log + kWh) | 25 |
| `solar_w` has Power-to-kWh process (ID 4) | 20 |
| All 3 battery inputs have non-empty process lists | 25 |
| ≥4 new pvbms/solar/battery feeds exist | 20 |
| Dashboard named 'Solar Storage Monitor' exists with ≥4 widgets | 10 |
| **Total** | **100** |
| **Pass threshold** | **≥60** |

## Verification Strategy

`export_result.sh` queries the database for:
- Each `pvbms` input's `processList` column in the `input` table
- Count of feeds matching solar/battery tags or names
- Dashboard existence and widget count from `dashboard` table

`verifier.py` scores against the criteria above.

## Key Database Schema

```
input table:  id, userid, nodeid, name, processList
feeds table:  id, userid, name, tag, engine, interval
dashboard table: id, userid, name, json
```

Process ID reference:
- `1:<feed_id>` = Log to Feed
- `4:<feed_id>` = Power to kWh (accumulation)

## Starting State

- Node `pvbms` has 4 inputs created (solar_w, battery_soc, battery_charge_w, battery_discharge_w)
- All `pvbms` input process lists are **empty**
- No feeds tagged pvbms/solar/battery exist
- Firefox is open at the Inputs page

## Credentials

- URL: http://localhost
- Username: admin
- Password: admin
