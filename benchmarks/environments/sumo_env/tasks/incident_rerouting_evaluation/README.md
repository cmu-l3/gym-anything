# Task: incident_rerouting_evaluation

## Occupation Context
**Role:** Emergency Management Directors (11-9161.00)
**Industry:** Public Administration and Government

## Task Description
An emergency management analyst must evaluate the traffic network's resilience to a major incident on the Bologna Acosta corridor. The agent must run a baseline simulation, simulate an incident by closing key edges using SUMO's rerouter mechanism, run the incident scenario, compare network performance metrics, and write an incident impact assessment with resilience analysis and recommendations.

## Difficulty: very_hard
- Agent must understand SUMO's rerouter mechanism (closingReroute, destProbReroute)
- Must create valid rerouter additional XML files with correct edge references
- Must create a modified sumocfg that includes additional rerouter file
- Must run both baseline and incident simulations
- Must parse tripinfo XML to compute network-wide performance metrics
- Must produce structured CSV and professional incident assessment report
- No UI path provided -- goal only

## Verification Criteria (100 points)
1. C1 (15 pts): Baseline simulation ran and network performance CSV produced
2. C2 (20 pts): Rerouter additional file created with valid rerouter elements closing >= 2 edges
3. C3 (15 pts): Incident sumocfg created and incident simulation ran
4. C4 (20 pts): Incident network performance CSV with valid numeric data
5. C5 (15 pts): Incident assessment report with location, comparison, resilience analysis
6. C6 (15 pts): Incident scenario shows plausible network degradation

## Data / Scenario
- Scenario: `/home/ga/SUMO_Scenarios/bologna_acosta/`
- Initial edge data saved to `/tmp/incident_rerouting_evaluation_initial_data.json`
- Baseline metrics: `/home/ga/SUMO_Output/baseline_network_performance.csv`
- Incident metrics: `/home/ga/SUMO_Output/incident_network_performance.csv`
- Rerouter file: `/home/ga/SUMO_Scenarios/bologna_acosta/incident_rerouters.add.xml`
- Report: `/home/ga/SUMO_Output/incident_assessment_report.txt`
