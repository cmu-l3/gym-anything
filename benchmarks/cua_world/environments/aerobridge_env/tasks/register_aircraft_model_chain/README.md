# Task: register_aircraft_model_chain

## Overview

Registering a new drone in Aerobridge requires a three-level hierarchy:
**Type Certificate → Aircraft Model → Aircraft Assembly → Aircraft**. Each level must
exist before the next can be created. This task requires navigating three separate
admin sections in the correct order.

## Goal

Register a new drone model and aircraft through the full chain:

1. **Create Aircraft Model "Nile Scout 200"** in Registry > Aircraft Models:
   - Category: ROTORCRAFT
   - Sub-category: Multirotor
   - Series: 2024.1
   - Mass: 1200 (grams)
   - Max certified takeoff weight: 1.500
   - Max speed: 15
   - Link to the existing Type Certificate (the only one in the system)

2. **Create Aircraft Assembly** in Registry > Aircraft Assemblies:
   - Aircraft model: Nile Scout 200 (the model just created)
   - Status: Complete

3. **Register Aircraft "NS-001"** in Registry > Aircraft:
   - Name: NS-001
   - Final assembly: the new assembly for Nile Scout 200
   - Operator: Electric Inspection
   - Manufacturer: Aerobridge Drone Company
   - Flight controller ID: NSCTRL112233
   - Status: Active

## Data

- **Application**: Aerobridge admin panel at `http://localhost:8000/admin/`
- **Login**: `admin` / `adminpass123`
- **Existing Type Certificate**: ID `75f358c6-e8d3-46aa-a3de-172bdcea469d`
  (the only TypeCertificate in the system — it appears in the dropdown)
- **Existing Aircraft Models**: only "Aerobridge F1" exists
- **Operator "Electric Inspection"**: must be selected as operator for NS-001
- **Manufacturer "Aerobridge Drone Company"**: role=Assembler, shows as "Aerobridge" in dropdown

## Starting State

- No AircraftModel named "Nile Scout 200" exists
- No Aircraft named "NS-001" exists

## Success Criteria

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| AircraftModel "Nile Scout 200" exists | 20 | name match |
| Model has category = ROTORCRAFT (2) | 15 | `category == 2` |
| AircraftAssembly created for Nile Scout 200 | 25 | `assembly.aircraft_model.name == 'Nile Scout 200'` |
| Aircraft "NS-001" created | 20 | name match |
| Aircraft uses the new assembly | 20 | `aircraft.final_assembly.aircraft_model.name == 'Nile Scout 200'` |
| **Total** | **100** | Pass threshold: **60** |

## Verification Approach

`export_result.sh` queries the database to check all three records. The verifier
validates the chain: AircraftModel → AircraftAssembly → Aircraft.

Anti-gaming: setup records initial counts of AircraftModel, AircraftAssembly, and Aircraft.
Wrong-chain detection: verifier explicitly checks that the aircraft's assembly points to the new model.

## Notes

- Aircraft Models admin: **Registry > Aircraft Models**
- Aircraft Assemblies admin: **Registry > Aircraft Assemblies**
- Aircraft admin: **Registry > Aircraft**
- AircraftAssembly shows in dropdown as " Model: <model_name> / Series: <series>"
- The new assembly will show as " Model: Nile Scout 200 / Series: 2024.1" — distinct from existing ones
- TypeCertificate in AircraftModel shows as its `type_certificate_id` UUID value
