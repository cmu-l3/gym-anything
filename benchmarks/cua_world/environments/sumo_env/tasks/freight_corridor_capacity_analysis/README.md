# Task: freight_corridor_capacity_analysis

## Occupation Context
**Role:** Logisticians (13-1081.00)
**Industry:** Transportation and Material Moving

## Task Description
A logistics operations analyst must evaluate whether a Bologna corridor can handle 80 additional heavy freight trucks during morning peak hours. The agent must create realistic truck vehicle type definitions, add them to the simulation, run the modified simulation, produce a before-after capacity analysis CSV report comparing baseline vs. truck-loaded metrics, and write a professional recommendation on corridor feasibility.

## Difficulty: very_hard
- Agent must understand SUMO vehicle type XML schema and emission class parameters
- Must generate 80 truck vehicle definitions with realistic physical parameters (weight, length, emission class)
- Must create valid route definitions using existing network edges
- Must configure and run the simulation headless to produce tripinfo output
- Must parse tripinfo XML output to compute aggregate metrics
- Must produce properly structured CSV and professional recommendation
- No UI path provided -- goal only

## Verification Criteria (100 points)
1. C1 (15 pts): Truck vehicle type definitions exist with realistic parameters
2. C2 (20 pts): At least 60-80 truck vehicles added to simulation routes
3. C3 (15 pts): Modified simulation ran and produced tripinfo output
4. C4 (25 pts): CSV report has correct structure, required metrics, and valid numeric values
5. C5 (15 pts): Professional recommendation file with substantive analysis and clear determination
6. C6 (10 pts): Report values are numerically plausible (wrong-target gate)

## Data / Scenario
- Scenario: `/home/ga/SUMO_Scenarios/bologna_acosta/`
- Baseline tripinfo pre-computed by setup script
- Baseline stats saved to `/tmp/freight_corridor_baseline_stats.json`
- Output report: `/home/ga/SUMO_Output/corridor_capacity_report.csv`
- Output recommendation: `/home/ga/SUMO_Output/corridor_recommendation.txt`
