# Coral Bleaching Thermal Stress Assessment (`coral_bleaching_thermal_stress@1`)

## Overview

This task tests the agent's ability to operate NASA Panoply as a marine biologist performing operational coral reef thermal stress monitoring. The agent must interpret a professional analysis request, navigate SST climatology data, produce two distinct plot exports, and write a scientifically accurate thermal stress assessment report. Success requires domain knowledge of coral bleaching thresholds and Indo-Pacific oceanography — the agent cannot succeed by random clicking.

## Domain Context

**Occupation:** Marine Biologist / Coral Reef Ecosystem Scientist
**Organization:** NOAA Coral Reef Watch
**Industry:** Marine Conservation / Government Environmental Science

NOAA Coral Reef Watch (CRW) issues operational bleaching alerts by monitoring sea surface temperature relative to the maximum monthly mean for each reef location. A sustained SST anomaly > 1°C above the long-term mean (the bleaching threshold, typically ~28.2°C in the Indo-Pacific) triggers a Bleaching Watch → Warning → Alert → Alert Level 2 progression. CRW scientists routinely use Panoply to visualize NOAA OI SST data and compare monthly climatologies across reef regions.

## Goal

The agent must:
1. Read the monitoring request at `~/Desktop/reef_monitoring_request.txt`
2. Open the NOAA OI SST v2 climatology dataset and navigate to August (peak thermal stress month)
3. Identify the most thermally stressed reef region from three designated areas (Indo-Pacific Warm Pool, Coral Triangle, Caribbean)
4. Export a global SST map to `~/Documents/ReefStress/reef_stress_global_aug.png`
5. Export a zoomed hotspot map to `~/Documents/ReefStress/reef_stress_hotspot.png`
6. Write a structured assessment report to `~/Documents/ReefStress/thermal_stress_report.txt`

## Expected End State

- `~/Documents/ReefStress/reef_stress_global_aug.png` — valid PNG, ≥ 20KB, created during task
- `~/Documents/ReefStress/reef_stress_hotspot.png` — valid PNG, ≥ 15KB, created during task
- `~/Documents/ReefStress/thermal_stress_report.txt` containing:
  - `HOTSPOT_REGION:` populated with a named region
  - `PEAK_SST:` ≥ 28.0°C (the Indo-Pacific Warm Pool in August exceeds 28.2°C)
  - `BLEACHING_RISK: HIGH` (correct classification given threshold)
  - `MONITORING_DATE: August`
  - `REGIONS_ASSESSED:` listing the three assessed regions

## Success Criteria and Verification Strategy

**Pass threshold:** 80/100 points (requires at least 3 of 4 criteria)

| Criterion | Points | Method |
|-----------|--------|--------|
| Global SST plot exported | 25 | File existence, timestamp ≥ task start, size ≥ 20KB |
| Hotspot plot exported | 25 | File existence, timestamp ≥ task start, size ≥ 15KB |
| Report complete with all required fields | 25 | Parse `thermal_stress_report.txt` for HOTSPOT_REGION, PEAK_SST, BLEACHING_RISK |
| Scientific correctness: PEAK_SST ≥ 28°C AND BLEACHING_RISK = HIGH | 25 | Numeric parse of PEAK_SST; string match for BLEACHING_RISK |

## Data Reference

- **Dataset:** NOAA OI SST v2 Long-Term Mean 1991–2020
- **File:** `/home/ga/PanoplyData/sst.ltm.1991-2020.nc`
- **Variable:** `sst` (Sea Surface Temperature, °C)
- **Key time index:** 7 (0-indexed) = August
- **Bleaching threshold:** 28.2°C (from NOAA CRW methodology)
- **Expected PEAK_SST range:** 28.0–33.0°C (Indo-Pacific Warm Pool / Persian Gulf in August)

## Edge Cases and Potential Issues

- Agent may report SST in Kelvin if they misread units — parse error will fire in verifier; partial credit still awarded for file delivery
- Agent may create only a global plot and skip the zoomed hotspot — loses 25 pts but can still pass (75 pts)
- Agent may navigate to wrong month (January vs. August) — PEAK_SST will be too low, losing the scientific correctness criterion
- Panoply time navigation: months are 0-indexed in the variable array; Panoply displays them as "Jan"/"Feb" etc. in the time step selector
