# Task: multimodal_person_trip_analysis

## Occupation Context
**Role:** Urban and Regional Planners (19-3051.00)
**Industry:** Professional, Scientific, and Technical Services

## Task Description
A multimodal transportation planner must evaluate transit accessibility along the Bologna Acosta corridor. The agent must run a simulation with stop-output enabled, analyze bus vs. private car performance, parse stop-level data to identify underserved bus stops, and propose a new bus route to fill service gaps.

## Difficulty: very_hard
- Agent must understand SUMO's --stop-output option and its XML format
- Must parse tripinfo to separate bus vs. private car performance metrics
- Must parse stop-output XML for per-stop dwell times and headway computation
- Must identify underserved stops based on visit count and headway thresholds
- Must create valid SUMO bus route XML with stop elements and edge references
- Must create modified sumocfg including the new route file
- Must produce multiple structured CSVs and professional transit assessment
- No UI path provided -- goal only

## Verification Criteria (100 points)
1. C1 (15 pts): Baseline simulation ran with tripinfo and modal performance CSV produced
2. C2 (20 pts): Bus stop analysis CSV with per-stop metrics (dwell time, headway)
3. C3 (15 pts): Underserved stops identified with valid gap reasons
4. C4 (20 pts): New bus route file created with stops at underserved locations + improved sumocfg
5. C5 (15 pts): Transit assessment report with modal analysis, gaps, and improvement proposals
6. C6 (15 pts): Stop-output XML generated (simulation configured correctly)

## Data / Scenario
- Scenario: `/home/ga/SUMO_Scenarios/bologna_acosta/`
- 35 bus stops, 157 bus vehicles, ~8622 private vehicles
- Initial bus stop data saved to `/tmp/multimodal_person_trip_analysis_initial_data.json`
