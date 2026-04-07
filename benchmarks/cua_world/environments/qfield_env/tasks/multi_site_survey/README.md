# Multi-Site Conservation Survey (`multi_site_survey@1`)

## Overview

This task evaluates the agent's ability to perform a multi-location field survey workflow in QField. The agent must navigate to three different capital cities across South America, create a new observation point at each location, and fill in site-specific attributes — simulating a realistic conservation field assessment spanning multiple sites.

## Rationale

**Why this task is valuable:**
- Tests repeated multi-step workflows across distant geographic locations
- Requires combining search/navigation, feature creation, and attribute entry in a sustained session
- Evaluates consistency of data entry across multiple features
- Exercises QField's core mobile data collection pipeline end-to-end

**Real-world Context:** A forest and conservation worker is conducting a quarterly habitat assessment across three South American capital cities. At each site, they must record an observation point with standardized survey attributes.

## Task Description

**Goal:** Navigate to three specific South American capital cities in the QField map, and at each one create a new observation/survey point feature with prescribed attributes.

**Starting State:** QField is open with the `world_survey.gpkg` GeoPackage loaded.

**Expected Actions:**

1. **Site 1 — Brasília, Brazil:**
   - Navigate to Brasília (approx -15.78°S, -47.93°W)
   - Create a new point feature
   - Attributes:
     - `observation_type`: `habitat_survey`
     - `observer`: `Rivera`
     - `notes`: `Cerrado biome assessment - dry season`

2. **Site 2 — Lima, Peru:**
   - Navigate to Lima (approx -12.05°S, -77.04°W)
   - Create a new point feature
   - Attributes:
     - `observation_type`: `habitat_survey`
     - `observer`: `Rivera`
     - `notes`: `Coastal desert transition zone`

3. **Site 3 — Buenos Aires, Argentina:**
   - Navigate to Buenos Aires (approx -34.60°S, -58.38°W)
   - Create a new point feature
   - Attributes:
     - `observation_type`: `habitat_survey`
     - `observer`: `Rivera`
     - `notes`: `Pampas grassland fringe monitoring`

**Final State:** The observations layer in `world_survey.gpkg` contains three new point features, each located near its respective capital city and carrying the correct attributes.

## Verification Strategy

### Primary Verification: GeoPackage Database Query
The verifier extracts the GeoPackage and checks:
1. **Count:** Exactly 3 new records created.
2. **Attributes:** Matches expected Observer, Type, and Notes.
3. **Location:** Points are within 2 degrees of target cities.

### Secondary Verification: VLM Trajectory
- Checks trajectory frames to confirm navigation to different map regions.
- Verifies forms were filled manually.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| 3 New Records | 15 | Exactly 3 new records found |
| Brasília Valid | 25 | Location and attributes correct |
| Lima Valid | 25 | Location and attributes correct |
| Buenos Aires Valid | 25 | Location and attributes correct |
| Anti-Gaming | 10 | Records created after task start |
| **Total** | **100** | |

Pass Threshold: 65 points (Must get at least 2 sites fully correct)