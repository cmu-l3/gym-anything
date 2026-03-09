# Task: create_survey_mission

## Overview

Drone operators use Aerobridge to plan and manage missions end-to-end. A complete
mission requires two interdependent records: a **Flight Plan** (the geographic route)
and a **Flight Operation** (the execution record that links the plan to a specific
drone, pilot, and operator). This task requires creating both in the correct order.

## Goal

Create a complete aerial survey mission for the Kolkata port area:

1. **Create Flight Plan "Kolkata Port Survey"** with:
   - A valid GeoJSON Polygon covering the survey area near Kolkata port
     (latitude ~22.5726, longitude ~88.3639)
   - Non-empty JSON content in the Plan File JSON field
   - The plan should be marked as editable

2. **Create Flight Operation "Kolkata Port Inspection"** referencing the new plan:
   - Drone: F1 #2
   - Pilot: Niteesh Pavani
   - Operator: Electric Inspection
   - Purpose: photographing
   - Type of operation: VLOS
   - Start datetime: 2026-03-01 09:00:00
   - End datetime: 2026-03-01 11:00:00

## Data

- **Application**: Aerobridge admin panel at `http://localhost:8000/admin/`
- **Login**: `admin` / `adminpass123`
- **Existing drone "F1 #2"**: ID `0450852f-856e-4ecb-beb6-01ccded8529d`
- **Pilot "Niteesh Pavani"**: linked to operator Electric Inspection
- **Operator "Electric Inspection"**: ID `566d63bb-cb1c-42dc-9a51-baef0d0a8d04`
- **Existing flight plans**: "Flight Plan A" (must NOT be used for the operation)

## Starting State

- No flight plan named "Kolkata Port Survey" exists
- No flight operation named "Kolkata Port Inspection" exists
- There is one existing flight plan: "Flight Plan A"
- There are two existing flight operations

## Success Criteria

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| FlightPlan "Kolkata Port Survey" exists | 20 | name match in FlightPlan table |
| FlightPlan has valid GeoJSON (Polygon or Point) | 20 | `geo_json` field is parseable JSON with type field |
| FlightOperation "Kolkata Port Inspection" exists | 20 | name match in FlightOperation table |
| FlightOperation references the NEW Kolkata plan | 25 | `flight_plan_id` != existing "Flight Plan A" ID |
| FlightOperation drone is F1 #2 | 15 | `drone_id` matches F1 #2 |
| **Total** | **100** | Pass threshold: **60** |

## Verification Approach

`export_result.sh` queries the database for both records. The verifier checks that
both exist and that the operation correctly references the new plan (not the old one).

Anti-gaming: setup records the initial FlightPlan and FlightOperation counts.
Wrong-plan detection: verifier explicitly checks the operation's `flight_plan_id`
against the known existing "Flight Plan A" ID.

## Notes

- Flight Plans are in **GCS Operations > Flight Plans**
- Flight Operations are in **GCS Operations > Flight Operations**
- A GeoJSON Polygon example: `{"type": "Polygon", "coordinates": [[[88.36, 22.57], [88.37, 22.57], [88.37, 22.58], [88.36, 22.58], [88.36, 22.57]]]}`
- Plan File JSON: can be any valid non-empty JSON object, e.g. `{"name": "Kolkata Port Survey"}`
- The Flight Operation's Drone dropdown shows aircraft by name ("F1 #1", "F1 #2")
- Pilot "Niteesh Pavani" appears as "Niteesh Pavani : Aerial Robots" in the dropdown
