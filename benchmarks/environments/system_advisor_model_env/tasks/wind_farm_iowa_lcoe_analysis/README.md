# wind_farm_iowa_lcoe_analysis

## Domain Context

Wind energy development in the US Midwest (Iowa ranks #2 nationally in wind capacity). Wind energy sales representatives and systems engineers use SAM's wind power model to evaluate site-specific turbine configurations and compute LCOE before committing to a turbine procurement contract. Iowa's high ridgeline wind resources (mean 7+ m/s at 80m per NREL Wind Toolkit) are among the most economically attractive in the US.

## Task Overview

Evaluate three commercial turbine configurations for a proposed 10 MW wind farm near Ames, Iowa and identify which delivers the lowest LCOE.

**Turbine configurations:**
1. Vestas V90-2.0MW — 90m rotor, 80m hub, 2.0 MW
2. GE 1.6-100 — 100m rotor, 80m hub, 1.6 MW
3. Vestas V110-2.0MW — 110m rotor, 95m hub, 2.0 MW

**Financial parameters:** $1,450/kW capex, $42/kW-yr O&M, 25yr life, 7% discount rate, PTC $0.015/kWh for 10 years.

## Goal (End State)

A JSON file at `/home/ga/Documents/SAM_Projects/Iowa_Wind_LCOE_Analysis.json` containing simulation results for all three configurations with capacity factors, annual energy production (MWh), and LCOE values, plus identification of the optimal configuration.

## Success Criteria

- Output file exists and was created during the task window
- Wind simulation model used (not PVWatts — SAM's wind model uses different PySAM modules)
- All three turbine configurations evaluated
- Capacity factors in the physically plausible range for Iowa wind (28–58%)
- LCOE values in a realistic range for Midwestern wind (15–90 $/MWh)
- AEP consistent with a ~10 MW wind farm (15,000–70,000 MWh/yr total)
- Optimal configuration identified

## Verification Strategy

`export_result.sh` (runs in VM):
- Checks for Python files newer than task start containing wind-specific imports
- Parses output JSON for: num_configs, min_lcoe, max_cf, first_aep, optimal_config
- Writes `/tmp/task_result.json`

`verifier.py` (runs on host):
- 8 criteria, 100 points total, pass threshold: 60 AND (file_exists AND file_modified AND python/wind model ran)
- Independent cross-check copies and parses the actual output file
- Anti-bypass: caps score at 20 if no Python execution detected

## Schema Reference

Output JSON structure:
```json
{
  "configurations": [
    {
      "config_name": "Vestas V90-2.0MW",
      "num_turbines": 5,
      "total_capacity_mw": 10.0,
      "annual_energy_mwh": <float>,
      "capacity_factor_pct": <float>,
      "lcoe_real_usd_per_mwh": <float>,
      "npv_usd": <float>
    }
  ],
  "optimal_configuration": "<config_name>"
}
```

## Wind Resource Data

SAM includes wind resource files in its installation directory. Additional wind resource data for any US location (including Ames, IA) is available from the NREL Wind Toolkit via the NREL developer API at `developer.nrel.gov`. The path to SAM's wind resource directory can be found via SAM's GUI or from the SAM installation path.

## Edge Cases

- Iowa wind resource files may not be bundled with SAM; agent must discover whether to use bundled files or download from NRDB API
- GE 1.6-100 has different rated power (1.6 MW) so requires 7 turbines for ~10 MW; Vestas models need 5
- Wind resource file must match the expected format (SRW or similar) for SAM's wind model
- LCOE output may be in cents/kWh from some financial models; verify units
