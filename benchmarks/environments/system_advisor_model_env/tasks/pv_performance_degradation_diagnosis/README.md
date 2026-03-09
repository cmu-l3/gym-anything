# pv_performance_degradation_diagnosis

## Domain Context

PV system performance audits are routine work for Solar Energy Systems Engineers hired by commercial building owners. When a system underperforms, the typical root causes in desert climates are: (1) soiling from dust accumulation, (2) accelerated degradation from UV and thermal stress, and (3) shading from new obstructions. Quantifying these effects requires running SAM simulations at different soiling and degradation parameter values and comparing modeled output to observed meter data — a parametric "best-fit" analysis. In Las Vegas (Mojave Desert, 648m elevation), soiling rates of 5–12%/yr are common when systems are not cleaned, and degradation rates of 0.7–1.3%/yr are typical for hot-climate installations per NREL's Jordan & Kurtz (2012) meta-analysis.

## Task Overview

Forensic performance analysis for a 25 kW Las Vegas rooftop PV system showing ~17% production shortfall in Year 4. The client report at `/home/ga/client_system_report.json` provides system specifications and observed annual production data (Year 1–4). The agent must run a 42-combination parametric sweep of soiling × degradation rate and identify the best-fit explanation.

**Sweep:** Soiling [2, 4, 6, 8, 10, 12]% × Degradation [0.3, 0.5, 0.7, 0.9, 1.1, 1.3, 1.5]%/yr = 42 combinations.
**Target:** Observed Year 4 production = 35,290 kWh. Best fit: minimize absolute error vs. modeled Year 4.

## Goal (End State)

A JSON file at `/home/ga/Documents/SAM_Projects/LasVegas_Performance_Diagnosis.json` containing all 42 sweep results, the best-fit soiling/degradation combination, a root cause analysis coherent with the Las Vegas desert environment, and recommended remediation actions.

## Scenario Scaffolding Notes

The `client_system_report.json` is programmatically constructed scenario scaffolding (see `01_core_principles.md` "Acceptable Special Case" for debugging/repair tasks). All values are grounded in NREL PVWatts outputs for Las Vegas 25 kW systems and published NREL degradation/soiling research. Ground truth embedded in task metadata: soiling=8%, degradation=0.9%/yr.

## Success Criteria

- Output file exists and was created during the task window
- PySAM simulation used to model Year 4 production
- Parametric sweep performed (20+ combinations in output, 42 preferred)
- Best-fit error < 10% of observed Year 4 production (35,290 kWh)
- Observed production data (including Year 4 = 35,290 kWh) included in output
- Root cause analysis and remediation recommendations provided
- Best-fit soiling/degradation values physically plausible for Las Vegas

## Verification Strategy

`export_result.sh` (runs in VM):
- Checks Python files for PySAM imports and sweep pattern (loops, 35290 reference)
- Parses output JSON for: num_sweep_results, best_fit_error_pct, best_fit soiling/degradation, has_recommendations
- Writes `/tmp/task_result.json`

`verifier.py` (runs on host):
- 8 criteria, 100 points total, pass threshold: 60 AND (file_exists AND file_modified AND python ran)
- Best-fit error criterion worth 20 points (highest weight — core task output)
- Independent cross-check validates sweep count and diagnostic terminology
- Anti-bypass: caps score at 20 if no Python execution detected

## Schema Reference

```json
{
  "system_info": { ... from client_system_report.json ... },
  "observed_production": {
    "year1": 42180, "year2": 41050, "year3": 39420, "year4": 35290
  },
  "sweep_results": [
    {
      "soiling_pct": 2,
      "degradation_rate_pct_per_yr": 0.3,
      "modeled_year4_kwh": <float>,
      "error_kwh": <float>,
      "error_pct": <float>
    }
  ],
  "best_fit": {
    "soiling_pct": <float>,
    "degradation_rate_pct_per_yr": <float>,
    "modeled_year4_kwh": <float>,
    "error_pct": <float>,
    "diagnosis_text": "<text>"
  },
  "root_cause_analysis": "<text>",
  "recommended_actions": ["<action1>", "<action2>"]
}
```

## Ground Truth

- Injected soiling: 8% (Year 4 cleaning was deferred)
- Injected degradation: 0.9%/yr (hot desert site; 0.5%/yr is temperate baseline from NREL)
- Best-fit combination should achieve < 5% error vs. observed 35,290 kWh

## Edge Cases

- Las Vegas weather data may not be bundled with SAM; agent must fetch from NRDB API or use nearest available
- Year 4 degradation factor = (1 - 0.9/100)^3 = 0.9731 — three years of degradation since commissioning
- Soiling loss is applied on top of degradation; do not double-count standard baseline losses
- Best-fit may not be unique — multiple (soiling, degradation) combinations can produce similar errors; any combination with < 5% error is acceptable
