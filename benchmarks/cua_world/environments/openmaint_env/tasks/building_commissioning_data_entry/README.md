# Building Commissioning Data Entry

## Domain Context

When a commercial real estate company acquires a new building, the commissioning
agent must onboard it into the facility management system. This involves creating
the building record with all its hierarchical structure (floors, rooms) and
registering all major infrastructure assets with their serial numbers. The data
comes from a commissioning report prepared by building consultants.

**Occupation:** Maintenance and Repair Workers, General (SOC 49-9071.00)
**Industry:** Commercial Real Estate Development

## Goal

Enter complete building data from a commissioning report into OpenMaint. The
agent must create:
1. One Building record (Code: BLD-WESTPARK, "Westpark Office Tower")
2. Four Floor records linked to the building (Ground through 3rd floor)
3. Twelve Room records distributed across floors with correct linkages
4. Six infrastructure asset records with exact serial numbers, linked to the building
5. All existing demo data must be preserved (no deletions)

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 Building | 20 | Building created with correct Code and "Westpark" in description |
| C2 Floors | 20 | 4 floors created (10 pts) and linked to building (10 pts) |
| C3 Rooms | 25 | 12 rooms created (15 pts) and linked to correct floors (10 pts) |
| C4 Assets | 20 | 6 assets created (10 pts) with correct serials (5 pts) and building link (5 pts) |
| C5 Preserved | 15 | Existing buildings, floors, rooms, and assets not deleted |

**Pass threshold:** 60/100
**Score cap:** If significant existing data deleted (>10%), score capped at 60.

## Verification Strategy

- **Setup** discovers class names (Building, Floor, Room, CI/Asset) and their
  relational fields (Floor→Building, Room→Floor, Asset→Building). Records baseline
  counts and IDs for all four classes. Places commissioning report on desktop.
- **Export** searches for new records by expected Code values, checks building
  linkages, serial numbers, and floor linkages. Counts preserved existing records.
- **Verifier** scores each criterion based on creation counts, correct linkages,
  and serial accuracy. Do-nothing detection: if no new records of any type
  created, score = 0.

## Schema Reference

- **Building class:** Building (Code, Description, Address)
- **Floor class:** Floor (Code, Description, Building reference field)
- **Room class:** Room (Code, Description, Floor reference field)
- **Asset class:** CI, Asset, or InternalEquipment (Code, Description, SerialNumber, Building reference)
- **Baseline file:** `/tmp/bcd_baseline.json`
- **Result file:** `/tmp/bcd_result.json`

## Expected Records

### Floors
| Code | Description | Level |
|------|-------------|-------|
| FLR-WP-G | Ground Floor (Lobby) | 0 |
| FLR-WP-1 | First Floor (Office) | 1 |
| FLR-WP-2 | Second Floor (Office) | 2 |
| FLR-WP-3 | Third Floor (Executive) | 3 |

### Assets
| Code | Description | Serial Number |
|------|-------------|---------------|
| AST-WP-HVAC-01 | Trane Rooftop Unit | SN-TRANE-2025-RTU-4400 |
| AST-WP-HVAC-02 | Carrier Air Handler | SN-CARRIER-2025-AHU-7821 |
| AST-WP-ELEC-01 | Eaton Main Distribution Panel | SN-EATON-2024-MDP-1560 |
| AST-WP-ELEV-01 | Otis Gen2 Passenger Elevator | SN-OTIS-2025-GEN2-3391 |
| AST-WP-FIRE-01 | Simplex 4100U Fire Alarm Panel | SN-SIMPLEX-2025-4100U-0887 |
| AST-WP-GEN-01 | Cummins QSB7 Emergency Generator | SN-CUMMINS-2025-QSB-6244 |

## Task Input File

`/home/ga/Desktop/commissioning_report.txt` contains the full building
specification with building info, floor registry, room registry, and asset
inventory including serial numbers.

## Edge Cases

- The agent must create records in dependency order: Building first, then Floors
  (which reference Building), then Rooms (which reference Floors). Creating
  rooms before floors would leave them unlinked.
- Serial numbers must be entered exactly as specified — the verifier uses
  exact string comparison.
- The Room→Floor linkage field name varies across OpenMaint configurations.
  The setup script discovers it dynamically.
- Agent must navigate multiple class types (Building, Floor, Room, Asset)
  which may be in different UI modules.
