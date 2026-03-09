# Task: multizone_submetering_configuration

## Overview

A facilities manager at a commercial building needs to commission a three-zone energy
submetering system. Three smart meters have been installed and are actively posting
data to Emoncms, but no logging or dashboards have been configured. The task
requires full setup: feeds, process lists, and a comparison dashboard.

## Domain Context

Facilities managers use submetering to:
- Identify which circuit (HVAC, lighting, sockets) consumes the most energy
- Track cumulative kWh per zone for tenant billing or energy audits
- Build dashboards that allow at-a-glance comparison across zones

## Starting State

Three nodes are live with one input each (no feeds configured):
- `zone_hvac` / `power_w` — HVAC system power in Watts
- `zone_lighting` / `power_w` — Lighting circuit power in Watts
- `zone_sockets` / `power_w` — Socket distribution board power in Watts

## Goal

1. **Configure process lists** for all three zones:
   - Each `power_w` input must log to a named power feed (e.g. "HVAC Power")
   - Each `power_w` input must also accumulate energy using Power-to-kWh
     (separate feed per zone, e.g. "HVAC Energy kWh")

2. **Create feeds** — at least 6 feeds total (2 per zone: power + kWh)

3. **Dashboard** — Create a dashboard named **'Building Submetering'** with
   at least 4 widgets allowing comparison across zones

## Success Criteria

| Criterion | Points |
|-----------|--------|
| `zone_hvac/power_w` has ≥2 process steps | 20 |
| `zone_lighting/power_w` has ≥2 process steps | 20 |
| `zone_sockets/power_w` has ≥2 process steps | 20 |
| ≥6 new feeds created (power + kWh per zone) | 25 |
| Dashboard 'Building Submetering' exists with ≥4 widgets | 15 |
| **Total** | **100** |
| **Pass threshold** | **≥60** |

## Verification

- `export_result.sh` queries each zone input's processlist and counts feeds
- `verifier.py` scores all criteria

## Credentials

- URL: http://localhost
- Username: admin
- Password: admin
