# Task: Scenario Comparison — Electricity Generation Technologies

## Domain
Life Cycle Assessment — Energy Systems & Decarbonization (Industrial Ecologists, ONET 19-2041.03)

## Overview
Utility-scale electricity generation is one of the largest contributors to greenhouse gas emissions. This task requires an industrial ecologist to build and compare two complete LCA models — one for coal power and one for natural gas power — using actual USLCI inventory data. The comparison must cover both climate change impact (GWP) and acidification, providing the utility with actionable comparison data.

## Goal (End State)
A CSV file at `~/LCA_Results/electricity_scenarios.csv` containing:
- GWP and Acidification impact values for coal electricity and natural gas electricity
- The percentage reduction in GWP when switching from coal to natural gas
Both product systems must be independently built and calculated.

## Why This Is Hard
- Two completely independent product systems must be built (requires navigating USLCI process tree twice, for different technology categories)
- Must run identical LCIA setup twice and consistently compare results
- Requires domain knowledge about which processes in USLCI represent coal vs. natural gas generation
- Computing percentage difference requires interpreting and comparing results from two separate calculations
- The CSV comparison format must be deliberately constructed by the agent (not an automatic export)
- Full workflow: import → find coal process → build PS1 → calculate → record results → find NG process → build PS2 → calculate → compare → export

## Success Criteria
1. USLCI database and LCIA methods imported
2. Two product systems created (coal electricity + natural gas electricity)
3. LCIA calculations run for both with GWP and Acidification
4. Comparison CSV exported with both scenarios' values and percentage difference

## Verification Strategy
- Derby: `TBL_PRODUCT_SYSTEMS` count >= 2
- Derby: `TBL_IMPACT_CATEGORIES` count > 0
- File: CSV in ~/LCA_Results/ with size > 200 bytes
- Content: CSV contains both "coal" and "natural gas" (or "gas", "natural.gas", "NGCC") keywords
- Content: CSV contains numeric values and "%" or "percent" (percentage difference)
- Content: GWP/global warming data present

## Relevant USLCI Processes
**Coal electricity:**
- Search "coal" or "bituminous coal" in electricity/utilities category
- Processes like "electricity, at coal power plant" or "coal-fired power"
- May be under "Electricity/Coal" or "Utilities" categories

**Natural gas electricity:**
- Search "natural gas" or "NGCC" in electricity category
- Processes like "electricity, natural gas, at combined cycle plant"
- May include gas turbine, CCGT, or steam processes

## Key Difference from Task 1 (packaging)
While Task 1 compares packaging materials (consumer goods domain), this task:
- Focuses on energy systems (utility/industrial domain)
- Requires explicit % reduction calculation (not just side-by-side comparison)
- Targets both GWP AND Acidification (acid rain is a key coal-related impact)
- Requires understanding electricity grid intensity concepts
