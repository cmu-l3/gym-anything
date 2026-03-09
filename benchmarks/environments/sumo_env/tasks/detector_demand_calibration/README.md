# Task: detector_demand_calibration

## Occupation Context
**Role:** Operations Research Analysts (15-2031.00)
**Industry:** Transportation and Warehousing

## Task Description
A traffic data analyst must calibrate the Acosta corridor's traffic demand model against detector data. The agent must run a baseline simulation to get E1 detector outputs, generate synthetic observed data with scaling factors, calibrate route files to better match the observed counts, run the calibrated simulation, and produce a calibration assessment using the GEH statistic (the standard traffic engineering calibration metric).

## Difficulty: very_hard
- Agent must understand SUMO's E1 detector output format (XML with interval elements)
- Must parse detector output XML to extract nVehContrib per interval
- Must understand and compute the GEH statistic (industry standard calibration metric)
- Must modify route XML files to adjust traffic demand (add/remove vehicles, shift departures)
- Must create valid sumocfg referencing calibrated routes
- Must run multiple simulations and compare detector outputs
- Must produce structured calibration CSV and professional summary
- No UI path provided -- goal only

## Verification Criteria (100 points)
1. C1 (15 pts): Baseline simulation ran and detector counts CSV produced
2. C2 (10 pts): Observed reference counts CSV produced with plausible scaling
3. C3 (20 pts): Calibrated route file created with modifications
4. C4 (15 pts): Calibrated simulation ran and detector counts CSV produced
5. C5 (25 pts): Calibration report CSV with GEH statistics for baseline and calibrated
6. C6 (15 pts): Calibration summary with methodology, GEH<5 percentage, recommendations

## Data / Scenario
- Scenario: `/home/ga/SUMO_Scenarios/bologna_acosta/`
- 58 E1 detectors with freq=1800 writing to e1_output.xml
- Initial detector data saved to `/tmp/detector_demand_calibration_initial_data.json`
