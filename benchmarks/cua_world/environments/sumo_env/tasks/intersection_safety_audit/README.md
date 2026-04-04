# Task: intersection_safety_audit

## Occupation Context
**Role:** Occupational Health and Safety Specialists (29-9011.00)
**Industry:** Protective Service

## Task Description
A safety specialist must conduct a surrogate safety analysis of signalized intersections in the Bologna Acosta corridor. The agent must configure SUMO's SSM (Surrogate Safety Measures) device to track TTC and DRAC metrics, run the simulation, parse the SSM output XML to identify conflict events per junction, produce a safety audit CSV report with risk ratings, and write a summary identifying the highest-risk junction with countermeasure recommendations.

## Difficulty: very_hard
- Agent must understand SUMO's SSM device configuration (device.ssm parameters)
- Must configure appropriate TTC and DRAC thresholds
- Must parse complex SSM XML output to extract conflict events
- Must map conflicts to signalized junctions in the network
- Must classify junctions by risk level based on conflict counts
- Must produce structured CSV and professional safety summary
- No UI path provided -- goal only

## Verification Criteria (100 points)
1. C1 (20 pts): SSM device configured and output file generated with conflict data
2. C2 (15 pts): Simulation ran to completion with tripinfo output
3. C3 (20 pts): Safety report CSV has correct 6-column structure with data rows
4. C4 (20 pts): Report contains plausible junction data with valid risk ratings and numeric conflict counts
5. C5 (15 pts): Summary identifies highest-risk junction and recommends countermeasures
6. C6 (10 pts): Reported junction IDs match real network junctions (wrong-target gate)

## Data / Scenario
- Scenario: `/home/ga/SUMO_Scenarios/bologna_acosta/`
- Junction info pre-computed by setup script to `/tmp/intersection_safety_junction_info.json`
- SSM output: `/home/ga/SUMO_Output/ssm_output.xml`
- Output report: `/home/ga/SUMO_Output/intersection_safety_report.csv`
- Output summary: `/home/ga/SUMO_Output/safety_audit_summary.txt`
