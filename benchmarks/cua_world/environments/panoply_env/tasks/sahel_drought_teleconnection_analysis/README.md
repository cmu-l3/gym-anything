# Sahel Drought Teleconnection Analysis (`sahel_drought_teleconnection_analysis@1`)

## Overview

This task tests the agent's ability to work with two different datasets within a single Panoply session (precipitation and SST), produce separate exports for each, and apply domain knowledge to correctly classify the sign of a well-documented climate teleconnection. The Sahel-ENSO relationship is one of the most studied remote forcing patterns in climate science; an agent with genuine domain knowledge will classify it as NEGATIVE (warm Pacific → Sahel drought), while an agent guessing will have only 1/3 probability of being correct.

## Domain Context

**Occupation:** Agricultural Climatologist / Food Security Analyst
**Organization:** USDA Economic Research Service / Foreign Agricultural Service
**Industry:** Agricultural Policy / International Food Security Assessment

The Sahel region (spanning Senegal, Mali, Burkina Faso, Niger, Chad, and Sudan) is home to over 100 million people dependent on rain-fed agriculture. The West African Monsoon, which delivers the Sahel's rainfall during July–September (JAS), is teleconnected to global sea surface temperature patterns — most importantly to the equatorial Pacific via the Walker circulation. USDA ERS analysts use climate datasets to inform annual food security assessments, drought early warning systems (FEWS NET), and humanitarian aid pre-positioning decisions.

The Sahel-ENSO teleconnection (NEGATIVE sign):
- **El Niño** (warm equatorial Pacific) → weakens Walker circulation → suppresses West African convergence → **Sahel drought**
- **La Niña** (cool equatorial Pacific) → strengthens Walker circulation → enhances moisture transport → **above-normal Sahel rainfall**

## Goal

The agent must:
1. Read the analysis mandate at `~/Desktop/sahel_drought_mandate.txt`
2. Open the NCEP precipitation dataset, navigate to July, and export a precipitation plot to `~/Documents/SahelDrought/sahel_precip_july.png`
3. Open the NOAA OI SST dataset, navigate to July, and export an SST plot to `~/Documents/SahelDrought/pacific_sst_july.png`
4. Write a teleconnection assessment report to `~/Documents/SahelDrought/teleconnection_report.txt`

## Expected End State

- `~/Documents/SahelDrought/sahel_precip_july.png` — valid PNG, ≥ 15KB, created during task
- `~/Documents/SahelDrought/pacific_sst_july.png` — valid PNG, ≥ 15KB, created during task
- `~/Documents/SahelDrought/teleconnection_report.txt` containing:
  - `ANALYSIS_REGION_1: Sahel`
  - `ANALYSIS_REGION_2: Equatorial_Pacific`
  - `TARGET_SEASON: JAS`
  - `ENSO_CONNECTION: NEGATIVE` (the correct scientific answer)
  - `SAHEL_PRECIP_PATTERN:` a description of the July precipitation band
  - `DATA_SOURCES:` listing the two datasets used

## Success Criteria and Verification Strategy

**Pass threshold:** 80/100 points (requires at least 3 of 4 criteria)

| Criterion | Points | Method |
|-----------|--------|--------|
| Sahel precipitation plot exported | 25 | File existence, timestamp ≥ task start, size ≥ 15KB |
| Pacific SST plot exported | 25 | File existence, timestamp ≥ task start, size ≥ 15KB |
| Teleconnection report with all required fields | 25 | Parse report for ANALYSIS_REGION_1, ANALYSIS_REGION_2, ENSO_CONNECTION |
| ENSO_CONNECTION = NEGATIVE | 25 | String match; 1/3 random probability — only domain knowledge reliably produces this |

## Data Reference

**Dataset 1 (precipitation):**
- **File:** `/home/ga/PanoplyData/prate.sfc.mon.ltm.nc`
- **Variable:** `prate` (Precipitation Rate, kg/m²/s)
- **Key time index:** 6 (July, 0-indexed)

**Dataset 2 (SST):**
- **File:** `/home/ga/PanoplyData/sst.ltm.1991-2020.nc`
- **Variable:** `sst` (Sea Surface Temperature, °C)
- **Key time index:** 6 (July, 0-indexed)

**Teleconnection reference:**
- ENSO_CONNECTION = NEGATIVE (El Niño → warm Pacific → Sahel drought; La Niña → cool Pacific → enhanced rainfall)
- This is described in the mandate's "Scientific Guidance" section to assist the agent

## Edge Cases and Potential Issues

- **Two-dataset workflow:** Agent must open a second dataset (SST) in Panoply alongside the already-open precipitation dataset; this requires using File > Open or dragging the SST file into the Panoply window
- **ENSO_CONNECTION guessing:** Three possible values (POSITIVE/NEGATIVE/NEUTRAL); mandating a verifiable scientific answer ensures domain knowledge matters
- **Precipitation in JAS vs. July:** The mandate specifies JAS as the target season but July as the plot month; agent should correctly identify July (index 6) for the export
- **Panoply multi-file session:** Panoply can open multiple files simultaneously; the Sources window shows variables from all open files. Agent must correctly select the right variable from the right dataset for each export
