# Task: public_transit_service_redesign

## Occupation Context
**Role:** Urban and Regional Planners (19-3051.00)
**Industry:** Architecture and Engineering

## Task Description
An urban transit planner must redesign the bus service in the Bologna Pasubio corridor to improve coverage. The agent must add at least 4 new bus stops to the network, create an express bus line with at least 3 vehicles at 10-minute headway, generate at least 50 pedestrian/person trips using public transit mode, run the modified simulation, and produce a service coverage CSV report and improvement summary.

## Difficulty: very_hard
- Agent must understand SUMO bus stop XML schema and placement on network edges
- Must create valid bus route definitions with proper stop sequences
- Must generate person trip definitions using SUMO's public transit mode
- Must modify the simulation configuration to include all new files
- Must run the simulation and verify it completes
- Must produce structured CSV with per-stop boarding/alighting data
- No UI path provided -- goal only

## Verification Criteria (100 points)
1. C1 (20 pts): At least 4 new bus stops added to the network
2. C2 (20 pts): Express bus line created with at least 3 vehicles
3. C3 (15 pts): At least 50 person trips added using public transit
4. C4 (15 pts): Modified simulation ran to completion with substantial output
5. C5 (20 pts): Service report CSV with correct structure, stop data, and new-stop markers
6. C6 (10 pts): Service improvement summary with transit-relevant terms

## Data / Scenario
- Scenario: `/home/ga/SUMO_Scenarios/bologna_pasubio/`
- Initial stop/bus counts saved to `/tmp/public_transit_initial_data.json`
- Output report: `/home/ga/SUMO_Output/transit_service_report.csv`
- Output summary: `/home/ga/SUMO_Output/transit_redesign_summary.txt`
