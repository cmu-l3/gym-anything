# csp_parabolic_trough_solar_multiple

## Domain Context

Concentrating Solar Power (CSP) parabolic trough systems are used by utility-scale developers at high-DNI desert sites. The solar multiple (SM) — ratio of collector field thermal output to power block input at design point — is the primary design variable that determines the trade-off between capital cost and energy production. Daggett, CA (Mojave Desert) has among the highest DNI in the US (~2,700 kWh/m2/yr) and is home to the SEGS parabolic trough installations. Choosing the right SM with thermal energy storage is a core engineering decision made by Solar Energy Systems Engineers before project financing.

## Task Overview

Parametric sweep of solar multiples (1.0–3.0 in steps of 0.25, 9 total) for a 50 MW CSP parabolic trough plant in Daggett, CA with 6-hour TES. Find the SM that maximizes NPV at a $80/MWh PPA price.

**Plant parameters:** $7,500/kW capex, $65/kW-yr O&M, 30yr life, 8.5% discount rate, 30% federal ITC, $80/MWh PPA.

## Goal (End State)

A JSON file at `/home/ga/Documents/SAM_Projects/Daggett_CSP_SM_Analysis.json` containing results for all 9 solar multiple values (annual energy, capacity factor, LCOE, NPV) and identification of the NPV-maximizing solar multiple.

## Success Criteria

- Output file exists and was created during the task window
- CSP parabolic trough model used (not PVWatts — different SAM technology family)
- 7 or more solar multiple values evaluated (full sweep preferred)
- Capacity factors in plausible CSP range (25–75%)
- LCOE values in realistic CSP range (60–350 $/MWh)
- AEP consistent with a 50 MW CSP plant (80,000–350,000 MWh/yr)
- Optimal SM identified within plausible range (1.5–2.75 for 6h TES at Daggett)

## Verification Strategy

`export_result.sh` (runs in VM):
- Checks Python files newer than task start for CSP-specific imports/parameters
- Parses output JSON for: num_sm_values, min_lcoe, max_cf, first_aep, optimal_sm
- Writes `/tmp/task_result.json`

`verifier.py` (runs on host):
- 8 criteria, 100 points total, pass threshold: 60 AND (file_exists AND file_modified AND python/csp ran)
- Independent file cross-check validates CSP terminology and SM range coverage
- Anti-bypass: caps score at 20 if no Python execution detected

## Schema Reference

```json
{
  "site": "Daggett, CA",
  "configurations": [
    {
      "solar_multiple": 1.0,
      "annual_energy_mwh": <float>,
      "capacity_factor_pct": <float>,
      "lcoe_real_usd_per_mwh": <float>,
      "npv_usd": <float>
    }
  ],
  "optimal_solar_multiple": <float>,
  "analysis_summary": "<text>"
}
```

## CSP SAM Model Discovery

SAM includes parabolic trough models: the Physical Parabolic Trough and the Empirical Parabolic Trough. Both are available as PySAM modules. The agent must discover which modules are appropriate via SAM's documentation or PySAM's available defaults (e.g., `help(PySAM.TroughPhysical)`). The Daggett weather file is bundled with SAM's solar resource library.

## Edge Cases

- The CSP model requires a DNI-specific weather file (not just GHI as for flat-plate PV)
- LCOE from CSP financial models may be in cents/kWh; convert to $/MWh (* 10)
- At very high SM (>2.5) with 6h TES, the plant may become storage-limited; expect diminishing CF gains
- NPV maximization may differ from LCOE minimization — the task asks for NPV optimization
