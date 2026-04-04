# Task: grid_tied_cost_monitoring

## Overview

A building energy manager is commissioning a net metering monitoring system for a
grid-tied facility. The smart meter posts real-time import and export readings, but
the import measurement requires a calibration correction factor before it can be
trusted for energy auditing or tenant billing.

## Domain Context

Commercial building energy managers who operate grid-tied solar + grid systems use
Emoncms to:
- Track both import (from grid) and export (to grid) energy flows
- Apply instrument calibration corrections to ensure metered data matches utility bills
- Accumulate kWh for billing reconciliation and carbon reporting
- Build dashboards for real-time visibility into net energy position

## Starting State

Node `smartmeter` has two inputs (no feeds configured):
- `import_w` — Grid import power in Watts (requires ×1.15 calibration)
- `export_w` — Grid export power in Watts (no correction needed)

## Goal

1. **Configure `import_w` process list** (minimum 3 steps):
   - Step 1: Multiply input by 1.15 (process ID 3 with value 1.15)
   - Step 2: Log to Feed → "Grid Import Power"
   - Step 3: Power to kWh → "Grid Import Energy kWh"

2. **Configure `export_w` process list** (minimum 2 steps):
   - Step 1: Log to Feed → "Grid Export Power"
   - Step 2: Power to kWh → "Grid Export Energy kWh"

3. **Create 4 feeds**: Grid Import Power, Grid Import Energy kWh,
   Grid Export Power, Grid Export Energy kWh

4. **Dashboard** named **'Grid Energy Monitor'** with ≥4 widgets

## Success Criteria

| Criterion | Points |
|-----------|--------|
| `import_w` has ≥ 3 process steps | 25 |
| `import_w` processlist includes a multiply step (process ID 3) | 20 |
| `export_w` has ≥ 2 process steps | 20 |
| ≥ 4 new smartmeter/grid feeds created | 20 |
| Dashboard 'Grid Energy Monitor' exists with ≥ 4 widgets | 15 |
| **Total** | **100** |
| **Pass threshold** | **≥ 60** |

## Emoncms Process ID Reference

```
Process ID 1:  Log to Feed          (arg: feed_id)
Process ID 3:  × (multiply)         (arg: numeric value)
Process ID 4:  Power to kWh         (arg: feed_id)
```

Example process list for import_w: `3:1.15,1:7,4:8`
(multiply by 1.15, log to feed 7, accumulate kWh in feed 8)

## Credentials

- URL: http://localhost
- Username: admin
- Password: admin
