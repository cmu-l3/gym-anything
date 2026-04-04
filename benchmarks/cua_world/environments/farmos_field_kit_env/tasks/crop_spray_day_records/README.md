# crop_spray_day_records

## Overview

**Role**: Precision Agriculture Technician
**Difficulty**: Very Hard
**Environment**: farmOS Field Kit (Android app, offline mode)

A Precision Agriculture Technician must document a complete day of pesticide spray operations in farmOS Field Kit. This is a mandatory workflow for regulatory compliance (USDA pesticide application records, EPA Worker Protection Standard) and crop protection audit trails. The technician must create 5 distinct farm logs of different types, each with specific times, done/not-done status, and detailed agronomic notes.

## Why This Is Hard

- Agent must create 5 separate logs, each requiring 5–8 UI interactions (tap +, enter name, change log type, set time, enter notes, toggle done, navigate back)
- Log types differ per entry (Activity, Input, Observation) — agent must correctly select each from the dropdown
- Time picker interaction is required for each log (7:30 AM, 8:00 AM, 10:30 AM, 12:30 PM, 1:30 PM)
- Done/Not Done status varies — agent must remember to toggle for the Observation log (must be NOT Done)
- Notes are detailed and multi-sentence — typing accuracy on mobile keyboard matters
- No UI navigation hints provided — agent must independently navigate the farmOS Field Kit interface

## Required Logs (in any order)

| # | Log Name | Type | Time | Done | Purpose |
|---|----------|------|------|------|---------|
| 1 | Pre-spray boom calibration check | Activity | 7:30 AM | Yes | Equipment verification before application |
| 2 | Glyphosate application Field 3 North | Input | 8:00 AM | Yes | Herbicide application record |
| 3 | Azoxystrobin fungicide Field 3 South | Input | 10:30 AM | Yes | Fungicide application record |
| 4 | Post-spray drift assessment | Observation | 12:30 PM | No | Drift monitoring (follow-up required) |
| 5 | Sprayer rinse and storage | Activity | 1:30 PM | Yes | Post-spray cleanup documentation |

## Verification Strategy

The export script navigates the app back to the Tasks list and dumps the Android UI hierarchy to `/sdcard/ui_dump_crop_spray.xml`. The verifier copies this XML and checks for each required log name in the text content.

**Scoring (100 points total)**:
- Each log name found in Tasks list: 20 points
- Pass threshold: 80 points (4 of 5 logs correct)

## Setup

The setup script:
1. Force-stops and clears farmOS app data for a clean state
2. Re-grants location permissions
3. Launches the app to the empty Tasks screen
4. Records the task start timestamp

## Domain Context

Pesticide application records are required under:
- EPA Worker Protection Standard (WCS) 40 CFR Part 170
- USDA NASS pesticide use surveys
- Farm bill conservation program compliance
- Crop insurance precision ag documentation

Real Precision Agriculture Technicians create these logs in the field immediately after each operation to ensure accuracy. The Input log type is specifically used for farm input applications (herbicides, fungicides, fertilizers). The Observation log type is used for field monitoring that requires follow-up action.
