# Model MHK Wave Energy Converter (`model_mhk_wave_energy@1`)

## Overview
This task evaluates the agent's ability to use PySAM's Marine Hydrokinetic (MHK) wave energy module to model a wave energy converter, configure device and loss parameters, run a simulation, and report metrics. It focuses on Python scripting using PySAM in an unfamiliar but emerging renewable energy technology domain.

## Rationale
**Why this task is valuable:**
- Tests Python API proficiency and documentation navigation with PySAM
- Requires understanding of marine hydrokinetic energy concepts
- Evaluates ability to configure loss parameters and interpret outputs
- Exercises self-consistency reasoning across physical quantities
- Diversifies the task pool beyond standard solar and wind use cases

**Real-world Context:** A Sustainability Specialist at a coastal municipality is evaluating the feasibility of deploying a wave energy converter. They need to generate first-order estimates of annual energy production and capacity factor using PySAM's default wave resource data.

## Task Description

**Goal:** Model a 300 kW wave energy converter using PySAM's `MhkWave` module, configure losses, and output results to JSON.

**Starting State:** The SAM desktop app is installed, PySAM is available, and a terminal is open.

**Expected Actions:**
1. Write a Python script using `PySAM.MhkWave`.
2. Load the default MhkWave configuration.
3. Set the system rated capacity to 300 kW.
4. Configure array spacing (0%), resource overprediction (5%), transmission (2%), downtime (5%), and additional losses (0%).
5. Execute the simulation.
6. Save the results to `/home/ga/Documents/SAM_Projects/wave_energy_results.json` containing specific keys for AEP, capacity factor, average power, loss percentages, and resource matrix dimensions.

**Final State:**
A valid JSON file exists at the target path with physically consistent and correctly configured results.

## Verification Strategy

### Primary Verification: File-based JSON parsing
- Verifies the JSON structure and required keys.
- Confirms configured capacity and loss percentages match the prompt perfectly.
- Validates the dimensions of the loaded wave resource matrix.

### Secondary Verification: Physics Consistency checks
- Validates `annual_energy_kwh` vs `device_average_power_kw`.
- Validates `capacity_factor_percent` vs `device_average_power_kw` and `system_capacity_kw`.
- Checks AEP and capacity factor for physically reasonable ranges.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| File Exists | 10 | Target JSON file is created |
| File Created | 10 | File was created/modified during task |
| Valid JSON & Keys | 10 | Parses correctly and contains all 11 keys |
| Capacity Correct | 10 | System capacity is 300 kW |
| Losses Correct | 10 | All 5 loss percentages match perfectly |
| AEP Reasonable | 10 | 0 < AEP < 2628000 kWh |
| CF Reasonable | 10 | 1% <= CF <= 65% |
| AEP Consistency | 10 | AEP matches Avg Power * 8760 |
| CF Consistency | 10 | CF matches Avg Power / Capacity |
| Matrix Check | 10 | Resource matrix > 2x2 |
| **Total** | **100** | |

Pass Threshold: 80 points with AEP consistency and file existence met.