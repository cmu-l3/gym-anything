# Wind-Assisted Cargo Ship Doldrums Routing (`wind_ship_doldrums_routing@1`)

## Overview

This task tests the agent's ability to use NASA Panoply to analyze Sea Level Pressure (SLP) climatology for maritime routing. The agent must act as a meteorological routing analyst for a modern wind-assisted cargo vessel, identify the "doldrums" (the equatorial low-pressure trough / ITCZ) in the Atlantic Ocean during September, and extract its latitudinal position and minimum pressure.

## Rationale

**Why this task is valuable:**
- **Visual Data Extraction:** Tests the agent's ability to identify a specific geophysical feature (a spatial minimum/trough) and map it to a latitude coordinate.
- **Domain Knowledge Trap:** The "meteorological equator" (ITCZ) is not the same as the geographic equator (0°). In September, the Atlantic ITCZ shifts significantly north (5°N–10°N). An agent that guesses "0°" without examining the data will fail.
- **Novel Persona:** Introduces a green-tech / modern sail-cargo maritime logistics scenario, distinct from standard climate science workflows.
- **Multi-modal Verification:** Combines file-based verification of software outputs with strict numerical plausibility checks and trajectory VLM checks.

**Real-world Context:** With the maritime industry pushing to decarbonize, wind-assisted propulsion (e.g., Flettner rotors, rigid sails) is experiencing a renaissance. However, these vessels are highly vulnerable to the "doldrums"—a persistent band of low atmospheric pressure near the equator characterized by weak, erratic winds and sudden squalls. A routing analyst must determine the exact latitudinal position of this low-pressure band during the voyage month to plan the optimal crossing track, minimizing the time the ship spends becalmed.

## Task Description

**Goal:** Analyze September Sea Level Pressure data to locate the doldrums in the central Atlantic, export a regional map, and produce a structured routing advisory report.

**Starting State:** 
- NASA Panoply is installed and available.
- No datasets are currently loaded.
- A request file is located at `~/Desktop/routing_request.txt`.
- Data is available in `~/PanoplyData/slp.mon.ltm.nc`.
- The target output directory `~/Documents/SailRouting/` does not yet exist.

**Expected Actions:**
1. Read the mandate at `~/Desktop/routing_request.txt` to understand the constraints.
2. Open the NCEP Sea Level Pressure (`slp.mon.ltm.nc`) dataset in Panoply.
3. Create a georeferenced plot of the `slp` variable.
4. Navigate the time dimension to **September**.
5. Zoom/pan the map to focus on the Equatorial Atlantic (approximately 20°S to 20°N, 50°W to 0°).
6. Export the plot as a PNG to `~/Documents/SailRouting/atlantic_slp_september.png`.
7. Analyze the plot or array data to find the latitude of the lowest pressure axis (the doldrums trough) in the central Atlantic.
8. Write a structured routing report to `~/Documents/SailRouting/doldrums_crossing_report.txt`.

**Final State:**
- `~/Documents/SailRouting/atlantic_slp_september.png` — valid image file, ≥ 15KB.
- `~/Documents/SailRouting/doldrums_crossing_report.txt` containing the structured findings.

## Expected Report Format

The agent must generate `doldrums_crossing_report.txt` with exactly these keys: