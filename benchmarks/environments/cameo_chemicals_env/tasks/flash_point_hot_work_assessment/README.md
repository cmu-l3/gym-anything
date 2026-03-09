# Flash Point Hazard Ranking for Hot Work Permit Assessment (`flash_point_hot_work_assessment@1`)

## Overview

This task evaluates the agent's ability to systematically look up flash point data for multiple chemicals from CAMEO Chemicals datasheets, rank them by fire ignition hazard, and classify them relative to a hot work temperature threshold. The agent must compile the results into a structured assessment document for a refinery safety engineer.

## Rationale

**Why this task is valuable:**
- Tests systematic multi-chemical property lookup and data extraction
- Requires quantitative comparison and ranking of numerical safety data
- Evaluates the agent's ability to apply a decision threshold to real hazard data
- Involves creating a structured output document from web-sourced information
- Directly relevant to a high-stakes industrial safety decision

**Real-world Context:** A refinery safety engineer is preparing to issue a hot work permit (for welding and grinding operations) in a chemical storage area. Before the permit can be issued, they must assess fire risk by determining which stored chemicals have flash points below the expected ambient work temperature of 100°F (37.8°C). Chemicals with flash points below this threshold can form ignitable vapor-air mixtures during hot work and require additional controls.

## Task Description

**Goal:** Look up the flash points of six specific chemicals on CAMEO Chemicals, rank them from most hazardous (lowest flash point) to least hazardous, classify each relative to a 100°F threshold, and save the results.

**Starting State:** Firefox is open and navigated to the CAMEO Chemicals homepage (https://cameochemicals.noaa.gov/).

**Chemicals to assess:**
1. Acetone
2. Methanol
3. Toluene
4. Xylenes
5. Acetic acid, glacial
6. Ethylene glycol

**Expected Actions:**
1. Search for each chemical on CAMEO Chemicals.
2. Locate the flash point value (°F) on each datasheet.
3. Rank the chemicals from lowest flash point (most hazardous) to highest.
4. Classify each: "HIGH RISK" (< 100°F) or "LOWER RISK" (≥ 100°F).
5. Save the assessment to `/home/ga/Documents/hot_work_flash_point_assessment.txt`.

**Required Output Format:**