# utility_pv_module_technology_lcoe

## Domain Context

Utility-scale PV bankability studies require detailed physics-based modeling that goes beyond simplified PVWatts assumptions. For a 50 MW project at a hot desert site like Daggett, CA (ambient temperatures regularly exceeding 40°C), the temperature coefficient of Pmax differs significantly between module technologies (mono-Si: ~0.36%/°C vs HJT: ~0.26%/°C vs CdTe: ~0.28%/°C). This difference in thermal performance can account for 2–5% variation in annual energy yield, shifting the LCOE comparison between technologies. Solar Energy Systems Engineers perform these detailed module technology comparisons to support procurement decisions on $50M+ projects.

## Task Overview

Compare three module technologies (standard mono-Si, premium HJT, CdTe thin film) for a 50 MW DC ground-mounted PV project in Daggett, CA using a cell-level physics model that accepts individual module electrical parameters. Compute LCOE and 25-year NPV for each technology.

**Module specs:** See task description for Vmp, Imp, Voc, Isc, temperature coefficients, and module price per watt.
**Financial:** BOS $0.45/W, inverter $0.06/W, EPC 10% overhead, O&M $14/kW-yr, 6% discount, 30% ITC, 60% debt at 5.5%, $35/MWh PPA.

## Goal (End State)

A JSON file at `/home/ga/Documents/SAM_Projects/Daggett_Module_Technology_LCOE.json` containing Year 1 energy production, capacity factor, total installed cost, LCOE, NPV, and IRR for each of the three technologies, plus identification of the LCOE-optimal technology.

## Success Criteria

- Output file exists and was created during the task window
- Detailed PV simulation model used (not simplified PVWatts — cell-level parameters required)
- All three module technologies evaluated
- Capacity factors in plausible range for Daggett single-axis tracking (22–35%)
- LCOE values in realistic utility PV range (20–80 $/MWh)
- AEP consistent with 50 MW at Daggett (90,000–160,000 MWh/yr)
- Optimal technology identified

## Verification Strategy

`export_result.sh` (runs in VM):
- Checks Python files for Pvsamv1/CEC-model-specific imports and parameters
- Parses output JSON for: num_technologies, min_lcoe, max_cf, first_aep, optimal_technology
- Writes `/tmp/task_result.json`

`verifier.py` (runs on host):
- 8 criteria, 100 points total, pass threshold: 60 AND (file_exists AND file_modified AND python ran)
- Independent cross-check validates LCOE values and tech names
- Pvsamv1 detection criterion worth 15 points (highest weight of any single criterion)
- Anti-bypass: caps score at 20 if no Python execution detected

## Schema Reference

```json
{
  "site": "Daggett, CA",
  "configurations": [
    {
      "tech_name": "Tech A - Standard Mono-Si",
      "module_efficiency_pct": 20.4,
      "module_price_per_w": 1.05,
      "total_installed_cost_usd": <float>,
      "annual_energy_year1_mwh": <float>,
      "capacity_factor_pct": <float>,
      "lcoe_real_usd_per_mwh": <float>,
      "npv_25yr_usd": <float>,
      "irr_pct": <float>
    }
  ],
  "optimal_technology": "<tech name>",
  "study_summary": "<text>"
}
```

## SAM Model Discovery

The simplified PVWatts model accepts only module efficiency and DC/AC ratio; it cannot differentiate between modules with the same efficiency but different temperature coefficients. The agent must discover that SAM's detailed PV model (available as a separate PySAM module) accepts individual CEC or Sandia module database parameters. Discovery path: SAM GUI shows multiple PV model options, or `import PySAM; dir(PySAM)` reveals available modules.

## Expected Analysis

At Daggett's extreme summer temperatures, HJT's lower temperature coefficient (-0.26%/°C vs -0.36%/°C) yields meaningfully higher annual energy despite the same rated power at STC. CdTe's lower module price ($0.95/W vs $1.05–1.20/W) reduces capex but its lower efficiency may require more land. The "optimal" technology by LCOE is not obvious — the agent must compute to determine the winner.

## Edge Cases

- CdTe has significantly different cell voltage/current characteristics (Vmp ~88V vs ~41V for Si); verify CEC parameter values are consistent with the technology
- LCOE from SingleOwner is in cents/kWh; multiply by 10 for $/MWh
- NPV depends on PPA price ($35/MWh); may be negative for some configurations
- Total installed cost must account for module + BOS + inverter + 10% EPC overhead
