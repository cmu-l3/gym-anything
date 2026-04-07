# Plan Remote Route (Kabul to Kandahar) (`plan_remote_route@1`)

## Overview
This task evaluates the agent's ability to plan a route between two specific remote locations, rather than from the current GPS position. The agent must configure the route planner to calculate a trip starting in Kabul and ending in Kandahar, verifying the ability to perform logistics planning and route previewing tasks.

## Rationale
**Why this task is valuable:**
- **Route Editing:** Tests the ability to modify the "Start Point" of a route, a distinct action from standard "Navigate to..." commands.
- **Logistics Planning:** Validates the workflow for estimating travel times and distances for future trips or remote teams.
- **Search Interaction:** Requires accurate searching and selection of multiple locations (Start and End).
- **Map Data Usage:** Utilizes the specific offline map data (Afghanistan) provided in the environment.

**Real-world Context:** A logistics coordinator for an aid organization in Kabul needs to estimate the driving distance and time for a supply convoy traveling to Kandahar tomorrow. Since they are currently at a different location (or the device GPS is elsewhere), they must manually configure the route start point to simulate the actual convoy path.

## Task Description

**Goal:** Calculate and display a route preview for a trip starting at **Kabul, Afghanistan** and ending at **Kandahar, Afghanistan**.

**Starting State:** Sygic GPS Navigation is open on the main map view. The Afghanistan map data is pre-installed. The device's current GPS location simulates a generic location and **must not** be used as the start point.

**Expected Actions:**
1. Open the search or route planning interface.
2. Set the **Destination** to "Kandahar" (select the city/center).
3. Change the **Start Point** from "Current Location" (or "My Position") to "Kabul" (select the city/center).
4. Initiate the route calculation.
5. Verify the screen displays the route preview with "Kabul" as the start and "Kandahar" as the destination.

**Final State:** 
- The app displays the **Route Preview** or **Route Summary** screen.
- The top bar (or route info) clearly shows the trip is from **Kabul** to **Kandahar**.
- Route statistics (distance/time) are visible.
- The map visualizes the path between the two cities.

## Verification Strategy

### Primary Verification: VLM Visual Analysis
The verifier captures the final screenshot and asks a Vision Language Model (VLM) to confirm the route parameters:
1. **Start Point:** Is the start location explicitly set to "Kabul"?
2. **Destination:** Is the destination set to "Kandahar"?
3. **Route Path:** Is a blue route line visible connecting two cities on the map?

### Secondary Verification: UI Hierarchy Analysis (XML)
The verifier dumps the UI hierarchy and parses the XML to find text matching the cities.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **Custom Start Point** | 40 | Start point is set to "Kabul" (not Current Location) |
| **Correct Destination** | 40 | Destination is set to "Kandahar" |
| **Route Calculated** | 20 | Route preview/map is displayed with valid statistics |
| **Total** | **100** | |

**Pass Threshold:** 80 points (Must have correct Start and End points).