# commercial_pv_battery_demand_charge

## Domain Context

Commercial PV+battery systems are increasingly evaluated not for energy arbitrage but for demand charge reduction. In Denver, CO (and many US commercial tariff structures), demand charges of $15–25/kW-month on the monthly peak 15-minute interval can represent 30–50% of a commercial electricity bill. Solar energy systems engineers evaluate battery sizing trade-offs against capital cost to determine which configuration maximizes financial return. This requires coupling PV simulation with battery dispatch modeling and utility rate analysis — a multi-feature SAM workflow distinct from simple PV simulation.

## Task Overview

Evaluate three battery configurations (100/200/400 kWh) co-located with a 250 kW PV system at a Denver, CO office park. The client pays $22/kW-month demand charges with ~180 kW peak. Compute demand savings, energy savings, payback period, NPV, and IRR for each; identify the optimal battery size.

**Rate structure:** $22/kW-month demand charge, $0.085/kWh energy, 2.5%/yr energy escalation.
**Battery specs:** LFP, 92% roundtrip efficiency, $400/kWh capex, 2.5%/yr fade, 15yr lifetime.
**Financial:** 30% ITC, 7% discount rate, 25yr analysis period.

## Goal (End State)

A JSON file at `/home/ga/Documents/SAM_Projects/Denver_Commercial_Battery_Analysis.json` containing financial results for all three battery configurations, including demand savings, energy savings, simple payback, NPV, and IRR, plus identification of the optimal battery size.

## Success Criteria

- Output file exists and was created during the task window
- Battery storage model used (SAM's Battery module, not just PV simulation)
- All three configurations evaluated
- Demand charge savings in physically plausible range ($5,000–$120,000/yr)
- NPV values in realistic commercial range ($-500,000 to $500,000)
- Payback periods in realistic range (2–30 years)
- Optimal configuration identified

## Verification Strategy

`export_result.sh` (runs in VM):
- Checks Python files newer than task start for Battery/Utilityrate imports
- Parses output JSON for: num_configs, min_payback, max_npv, first_demand_savings, optimal_config
- Writes `/tmp/task_result.json`

`verifier.py` (runs on host):
- 8 criteria, 100 points total, pass threshold: 60 AND (file_exists AND file_modified AND python/battery ran)
- Independent cross-check validates battery sizes and NPV count
- Anti-bypass: caps score at 20 if no Python execution detected

## Schema Reference

```json
{
  "site": "Denver, CO",
  "configurations": [
    {
      "config_name": "Config A: 100 kWh / 50 kW",
      "battery_kwh": 100,
      "battery_kw": 50,
      "annual_demand_charge_savings_usd": <float>,
      "annual_energy_savings_usd": <float>,
      "simple_payback_years": <float>,
      "npv_25yr_usd": <float>,
      "irr_pct": <float>
    }
  ],
  "optimal_configuration": "<config name>",
  "recommendation_summary": "<text>"
}
```

## SAM Battery Model Discovery

SAM includes battery storage models that couple with PV simulation. The battery dispatch can be configured for peak shaving (reducing demand charges) vs. self-consumption. The agent must discover SAM's battery module through PySAM documentation or SAM's GUI. A utility rate model (SAM's Utility Rate module) handles time-varying rates and demand charges.

## Data Source

Weather: Denver, CO weather data available from NREL NSRDB or downloadable via SAM's online weather fetch feature. The NRDB API key can be obtained free at developer.nrel.gov.

## Edge Cases

- Denver weather may not be bundled with SAM; agent must fetch or download
- Demand charge savings depend on battery dispatch strategy; peak shaving may not fully eliminate demand charges for all configurations
- IRR may be undefined (NaN) if NPV never turns positive within the analysis period; handle gracefully
- The 400 kWh battery may not be the NPV-optimal choice despite its larger capacity (higher capex)
