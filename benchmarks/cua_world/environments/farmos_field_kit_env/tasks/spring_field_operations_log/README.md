# spring_field_operations_log

## Overview

**Role**: Farmers, Ranchers, and Other Agricultural Managers
**Difficulty**: Very Hard
**Environment**: farmOS Field Kit (Android app, offline mode)

A grain farmer must document a complete spring field operations day in farmOS Field Kit, covering cover crop termination, soil sampling, and corn planting across two fields. These records support FSA program compliance, input cost tracking, agronomic decision-making, and future yield analysis. The farmer must create 5 logs spanning Activity, Input, and Observation types with precise agronomic data.

## Why This Is Hard

- Mixed log types: Activity ×2, Input ×2, Observation ×1
- Input log type must be used for planting records (non-default selection)
- Two nearly-identical planting logs (Fields 7 East and 8) require distinct, specific names — agent must correctly differentiate them
- The Observation log (log 5) must be marked NOT Done — agent must toggle done status to off
- Times span a realistic 10-hour workday (7:00 AM through 5:30 PM)
- Notes contain precision agriculture data: seed populations, in-furrow fertilizer rates, GPS settings, soil temperature — testing domain knowledge integration
- Total of 5 complete log entries requiring ~350 steps across the full workflow

## Required Logs (in any order)

| # | Log Name | Type | Time | Done | Purpose |
|---|----------|------|------|------|---------|
| 1 | Winter rye cover crop burndown | Activity | 7:00 AM | Yes | Cover crop termination spray |
| 2 | Grid soil sampling Field 5 | Activity | 9:00 AM | Yes | Nutrient management sampling |
| 3 | Corn planting Field 7 East 32500 population | Input | 11:30 AM | Yes | Planting record with seeding rate |
| 4 | Corn planting Field 8 32500 population | Input | 2:00 PM | Yes | Second field planting record |
| 5 | Field 7 East planting quality check | Observation | 5:30 PM | No | Post-plant verification (pending) |

## Verification Strategy

The export script navigates to the Tasks list and dumps the UI hierarchy to `/sdcard/ui_dump_spring.xml`. The verifier checks for each required log name.

**Scoring (100 points total)**:
- Each log name found in Tasks list: 20 points
- Pass threshold: 80 points (4 of 5 logs correct)

## Domain Context

Spring planting records are required for:
- USDA Farm Service Agency (FSA) farm program acres reporting
- Crop insurance policy unit mapping and APH yield records
- Conservation program (EQIP, RCPP) compliance documentation
- Agronomist records for fertility management (linked to soil sampling)
- Precision agriculture data for variable-rate seeding maps (next season)

The use of Input log type for planting records reflects farmOS convention: planting is a farm "input" operation (seeds + starter fertilizer applied to field). The Observation log is left open because emergence verification (a follow-up action) has not yet occurred — this is standard agronomic record-keeping workflow.
