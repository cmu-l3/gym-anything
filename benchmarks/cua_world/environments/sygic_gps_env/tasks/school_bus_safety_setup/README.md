# Task: school_bus_safety_setup

## Summary

Configure Sygic GPS Navigation for a school bus fleet per district safety policy. The transportation coordinator must set up a bus vehicle profile, enable arrive-in-direction, enable lane guidance, avoid ferries, and set distance units to miles.

## Occupation Context

**Primary occupation**: School Bus Drivers and Transit/Intercity Bus Drivers
**GDP relevance**: $74M economic output; school transportation is a regulated GPS use case where misconfiguration creates real safety risk

## Scenario

Maplewood Unified School District configures GPS before each semester. Five district requirements:

1. **Arrive-in-direction**: Mandatory — students board/alight without crossing in front of the bus.
2. **Lane guidance**: Mandatory — complex intersections near school zones require lane-by-lane guidance.
3. **No ferries**: District liability exclusion — buses must stay on road-only routes.
4. **Miles**: Federal reimbursement forms use miles; all route planning must match.
5. **Bus vehicle profile**: Named "School Bus", bus type, diesel, 2020, Euro 6.

## Difficulty: very_hard

Description gives only regulatory/policy context, no UI navigation steps or explicit setting names.

## Verification

Scoring (100 pts, pass=65):
| Criterion | Points |
|-----------|--------|
| Bus profile name contains 'school' or 'bus' | 20 |
| Vehicle type = BUS | 15 |
| Fuel=DIESEL, Year=2020, Emission=EURO6 | 15 |
| Bus profile is active | 15 |
| Arrive-in-direction enabled | 15 |
| Lane guidance enabled | 10 |
| Ferries avoided | 5 |
| Distance units = Miles | 5 |

## Setup Starting State

| Setting | Start Value | Target Value |
|---------|-------------|--------------|
| Extra vehicle profiles | none (only Vehicle 1) | School Bus added |
| Arrive-in-direction | false | true |
| Lane guidance | false | true |
| Avoid ferries | false | true |
| Distance units | Km (1) | Miles (0) |
