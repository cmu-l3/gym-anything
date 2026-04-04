# Task: traffic_calming_zone_design

## Occupation Context
**Role:** Civil Engineers (17-2051.00)
**Industry:** Architecture and Engineering

## Task Description
A civil engineer must design a 30 km/h traffic calming zone in the Bologna Acosta residential area. The agent must run a baseline simulation, identify and modify at least 8 residential edges to 30 km/h speed limits, optionally add speed bumps, run the calming simulation, and produce a before-after comparison CSV report and engineering summary documenting the zone design and impact on arterial traffic.

## Difficulty: very_hard
- Agent must understand SUMO network XML structure (edge speeds, lane attributes)
- Must identify residential edges by characteristics (speed, lane count, length)
- Must modify network speeds using netedit or direct XML editing with netconvert
- Must run baseline and modified simulations and compare outputs
- Must compute zone-specific and corridor-wide metrics from tripinfo
- Must produce structured CSV and professional engineering summary
- No UI path provided -- goal only

## Verification Criteria (100 points)
1. C1 (15 pts): Baseline simulation ran and tripinfo saved
2. C2 (20 pts): At least 8 network edges modified to 30 km/h (8.33 m/s)
3. C3 (15 pts): Calming simulation ran and tripinfo saved
4. C4 (25 pts): Before-after report CSV with correct columns, 5 required metrics, and valid numeric values
5. C5 (15 pts): Engineering summary with traffic calming and impact assessment terms
6. C6 (10 pts): Report shows plausible speed reduction in calming zone

## Data / Scenario
- Scenario: `/home/ga/SUMO_Scenarios/bologna_acosta/`
- Original edge speed data saved to `/tmp/traffic_calming_edge_data.json`
- Baseline tripinfo: `/home/ga/SUMO_Output/baseline_tripinfos.xml`
- Calming tripinfo: `/home/ga/SUMO_Output/calming_tripinfos.xml`
- Output report: `/home/ga/SUMO_Output/traffic_calming_report.csv`
- Output summary: `/home/ga/SUMO_Output/traffic_calming_summary.txt`
