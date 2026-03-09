# Task: arterial_signal_coordination

## Occupation Context
**Role:** Transportation Engineers (17-2051.01)
**Industry:** Architecture and Engineering

## Task Description
A traffic signal engineer must implement progressive signal coordination ("green wave") along the Bologna Acosta corridor. The agent must run a baseline simulation, analyze existing signal timing programs, compute inter-intersection offsets based on design speed, create a coordinated TLS configuration, run the coordinated simulation, and produce a before/after performance comparison with professional recommendations.

## Difficulty: very_hard
- Agent must understand SUMO TLS offset mechanics and signal coordination theory
- Must parse existing tlLogic XML to extract cycle lengths and phase structures
- Must compute offsets based on inter-intersection distances and design speed (50 km/h)
- Must create valid modified sumocfg referencing new TLS additional file
- Must run both baseline and coordinated simulations successfully
- Must parse tripinfo XML to compute corridor-level metrics (travel time, waiting time, time loss)
- Must produce structured CSV and professional engineering report
- No UI path provided -- goal only

## Verification Criteria (100 points)
1. C1 (15 pts): Baseline simulation ran and corridor metrics CSV produced with valid data
2. C2 (20 pts): Coordinated TLS file created with offset modifications for >= 4 intersections
3. C3 (15 pts): Modified sumocfg created and coordinated simulation ran with tripinfo output
4. C4 (20 pts): Coordinated corridor metrics CSV produced with valid numeric data
5. C5 (15 pts): Signal coordination report with offset rationale, before/after comparison, and percentage improvements
6. C6 (15 pts): Coordinated simulation shows plausible improvement in at least one corridor metric

## Data / Scenario
- Scenario: `/home/ga/SUMO_Scenarios/bologna_acosta/`
- TLS IDs: 209, 210, 219, 220, 221, 235, 273
- Initial TLS data saved to `/tmp/arterial_signal_coordination_initial_data.json`
- Baseline metrics: `/home/ga/SUMO_Output/baseline_corridor_metrics.csv`
- Coordinated metrics: `/home/ga/SUMO_Output/coordinated_corridor_metrics.csv`
- Report: `/home/ga/SUMO_Output/signal_coordination_report.txt`
