# Task: register_aircraft_with_detail

## Overview

Register a new drone in the Aerobridge system through three linked steps:
create the aircraft record, attach a regulatory detail record marking it as
officially registered, and schedule its first flight operation. This mirrors
real-world UAS fleet management where a newly purchased drone must be added to
the system, formally registered with aviation authorities, and then assigned to
an operation before it can fly.

## Goal

Create three related records in Aerobridge:

1. **Aircraft** — "Falcon Eye 3"
2. **AircraftDetail** — registration mark for Falcon Eye 3
3. **FlightOperation** — maiden flight using the new aircraft

## Starting State

- The Django admin is accessible at `http://localhost:8000/admin/`
  (credentials: `admin` / `adminpass123`)
- Firefox is already open to the admin login page
- Existing aircraft in the system: **F1 #1**, **F1 #2** (leave these untouched)
- "Falcon Eye 3" does **not** yet exist; neither does its detail record nor its
  maiden flight operation

## Required Steps

### Step 1 — Create Aircraft

Navigate to **Registry → Aircrafts → Add aircraft** and fill in:

| Field | Value |
|---|---|
| Name | Falcon Eye 3 |
| Flight controller ID | FE3CTRL334455 |
| Status | Active |
| Operator | A.J. August Photography |
| Manufacturer | Aerobridge Drone Company |
| Final assembly | *(select any available assembly)* |

### Step 2 — Create AircraftDetail

Navigate to **Registry → Aircraft details → Add aircraft detail** and fill in:

| Field | Value |
|---|---|
| Aircraft | Falcon Eye 3 *(the one you just created)* |
| Is registered | ✓ (checked) |
| Registration mark | IND/UP/2024/003 |

### Step 3 — Create FlightOperation

Navigate to **Gcs → Flight operations → Add flight operation** and fill in:

| Field | Value |
|---|---|
| Name | Falcon Eye 3 Maiden Flight |
| Drone | Falcon Eye 3 |
| Flight plan | Flight Plan A |
| Operator | A.J. August Photography |
| Pilot | Rakesh Kankipati |
| Purpose | photographing |
| Type of operation | VLOS |
| Start date/time | any future date/time |
| End date/time | any date/time after start |

## Success Criteria

| Criterion | Points |
|---|---|
| Aircraft "Falcon Eye 3" exists | 20 |
| Flight controller ID is "FE3CTRL334455" | 15 |
| AircraftDetail exists for Falcon Eye 3 | 20 |
| AircraftDetail is_registered == True | 15 |
| Registration mark == "IND/UP/2024/003" | 10 |
| FlightOperation "Falcon Eye 3 Maiden Flight" exists | 20 |
| **Total** | **100** |

**Pass threshold: 60 points**

## Verification Approach

A post-task export script queries the Django ORM for:
- The `Aircraft` with name `Falcon Eye 3`
- The `AircraftDetail` linked to that aircraft
- The `FlightOperation` named `Falcon Eye 3 Maiden Flight`

Results are written to `/tmp/register_aircraft_with_detail_result.json`, which
the verifier reads (via `copy_from_env`) to award points.

## Anti-Gaming Measures

- The verifier checks that `Falcon Eye 3` was **not** present at task start
  (baseline aircraft count is recorded by the setup script)
- The registration mark must match exactly: `IND/UP/2024/003`
- The FlightOperation must reference the **new** aircraft, not F1 #1 or F1 #2
