# Task: emission_zone_impact_study

## Occupation Context
**Role:** Environmental Scientists and Specialists (19-2041.00)
**Industry:** Life, Physical, and Social Science

## Task Description
An environmental scientist must conduct a before-after emission impact study for a proposed Low Emission Zone (LEZ) in the Bologna Pasubio corridor. The agent must run a baseline simulation with emission tracking, implement the LEZ using at least 2 strategies (edge restrictions, emission class changes, route modifications), run the LEZ simulation, produce an emission impact CSV report for 5 pollutants (CO2, CO, NOx, PMx, HC), and write a professional environmental impact summary with numerical results.

## Difficulty: very_hard
- Agent must understand SUMO's emission output configuration and HBEFA emission classes
- Must implement at least 2 of 3 LEZ strategies (edge disallow, vtype emission class changes, route modifications)
- Must configure emission-output option in simulation configuration
- Must run both baseline and LEZ simulations
- Must parse emission XML output to aggregate pollutant totals
- Must produce structured CSV and summary with specific numerical reduction percentages
- No UI path provided -- goal only

## Verification Criteria (100 points)
1. C1 (15 pts): Baseline simulation ran with emission output generated
2. C2 (20 pts): LEZ implemented using at least 2 of 3 strategies
3. C3 (15 pts): LEZ simulation ran with emission output generated
4. C4 (25 pts): Emission impact report CSV with 4 required columns, 5 required pollutants, and valid numeric data
5. C5 (15 pts): Environmental impact summary with environmental terms and numerical percentage results
6. C6 (10 pts): Report shows plausible emission reductions for multiple pollutants

## Data / Scenario
- Scenario: `/home/ga/SUMO_Scenarios/bologna_pasubio/`
- Initial emission classes and edge data saved to `/tmp/emission_zone_initial_data.json`
- Baseline emissions: `/home/ga/SUMO_Output/baseline_emissions.xml`
- LEZ emissions: `/home/ga/SUMO_Output/lez_emissions.xml`
- Output report: `/home/ga/SUMO_Output/emission_impact_report.csv`
- Output summary: `/home/ga/SUMO_Output/emission_impact_summary.txt`
