# Agricultural Cooperative First-Time Setup (`agri_coop_pesticide_setup@1`)

## Overview
This task evaluates the agent's ability to initialize a completely new facility in EPA Tier2 Submit and configure hazardous chemical reporting from scratch. It focuses on the agricultural sector, requiring the agent to correctly enter bulk fertilizer (Ammonium Nitrate) and a highly regulated EHS pesticide (Paraquat Dichloride).

## Rationale
**Why this task is valuable:**
- Tests complete facility initialization (NAICS, location, identification)
- Evaluates handling of both non-EHS and EHS (Extremely Hazardous Substance) materials
- Requires accurate entry of chemical identifying data (CAS numbers) and range codes
- Reflects a highly common real-world scenario (agricultural cooperatives tracking bulk chemicals)

**Real-world Context:** An Environmental Health and Safety Manager for "Heartland Agri-Coop" is preparing the facility's first-ever EPCRA Tier II report. The facility stores massive quantities of ammonium nitrate fertilizer and a smaller, but highly toxic, cache of paraquat dichloride. The manager must establish the facility profile and accurately report these two distinct hazard profiles.

## Task Description

**Goal:** Create a new facility profile for Heartland Agri-Coop, add Ammonium Nitrate and Paraquat Dichloride to the inventory with their respective hazard details, and export the submission file.

**Starting State:** EPA Tier2 Submit 2025 is installed and launched. No facilities exist in the current database.

**Expected Actions:**
1. Create a new Facility with the following details:
   - Facility Name: `Heartland Agri-Coop`
   - Street Address: `1500 Harvest Way`
   - City: `Grand Island`
   - State: `NE`
   - ZIP Code: `68803`
   - NAICS Code: `424910` (Farm Supplies Merchant Wholesalers)
2. Add the first chemical (Fertilizer):
   - Chemical Name: `Ammonium Nitrate`
   - CAS Number: `6484-52-2`
   - EHS: No
   - Physical State: Solid
   - Hazards: Oxidizer
3. Add the second chemical (Pesticide):
   - Chemical Name: `Paraquat Dichloride`
   - CAS Number: `1910-42-5`
   - EHS: Yes
   - Physical State: Liquid
   - Hazards: Acute toxicity
4. Export the final Tier II submission to exactly: `C:\Users\Docker\Documents\heartland_coop.t2s`

**Final State:** A valid `.t2s` submission file exists at `C:\Users\Docker\Documents\heartland_coop.t2s` containing the facility and both chemical records.

## Verification Strategy

### Primary Verification: File Content Analysis
The verifier extracts the generated `.t2s` file (which is a zipped XML structure) and programmatically verifies the presence of the facility name, zip code, and both chemical CAS numbers/names.

### Secondary Verification: VLM Trajectory Check
Uses a Vision-Language Model to sample trajectory frames during the agent's workflow to confirm it actively used the EPA Tier2 Submit interface to enter the data (preventing the agent from just writing a fake text file directly).

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| File Exists | 10 | The target `.t2s` file was successfully exported |
| Facility Identified | 10 | "Heartland Agri-Coop" found in the export file |
| Location Data | 10 | ZIP code "68803" and NAICS "424910" found |
| Ammonium Nitrate | 20 | CAS "6484-52-2" and name found in export |
| Paraquat Dichloride | 20 | CAS "1910-42-5" and name found in export |
| VLM Process Check | 30 | Trajectory shows the agent using the Tier2 Submit UI |
| **Total** | **100** | |

Pass Threshold: 60 points, and the file must exist.