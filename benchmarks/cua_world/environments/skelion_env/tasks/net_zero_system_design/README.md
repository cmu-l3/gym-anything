# Task: net_zero_system_design

## Occupation Context

**Primary occupation**: Energy Engineer (net-zero commercial building design)
**GDP relevance**: $2.28B (Skelion solar design category)
**Workflow**: Sizing a rooftop PV system to offset 100% of a building's annual electricity consumption, using peak sun hours and panel specifications to calculate the required panel count, then documenting the sizing in a professional report.

---

## Task Overview

GreenCore Engineering has been retained to design a net-zero PV system for a 220,000 kWh/year commercial office building in Austin, TX. The energy engineer (agent) must set the correct geographic location, use an energy sizing worksheet to determine the minimum panel count required for net-zero operation, place those panels using Skelion, and produce a formal System Sizing Report.

The building model `Solar_Project.skp` is open in SketchUp Make 2017 with Skelion installed.

---

## Goal (End State)

1. **Geographic location** set to Austin, TX — latitude 30.4103° N, longitude 97.8516° W (within ±0.50° tolerance)
2. **Minimum 63 solar panels** placed on the roof (per energy worksheet sizing; 63 is the documented minimum for this task, representing partial system)
3. **`System_Sizing_Report.txt`** saved to `C:\Users\Docker\Desktop\` containing:
   - Site location and coordinates
   - Number of panels placed
   - Estimated annual generation (kWh)
   - Net-zero feasibility statement

---

## Reference Data

`C:\Users\Docker\Desktop\energy_worksheet.txt` — placed by setup_task.ps1

Contains:
- Building annual consumption: 220,000 kWh/year
- Austin solar resource: 5.50 peak sun hours/day (real NREL PVWatts data)
- Panel specs: 400W, system derate 0.80
- Sizing calculation showing minimum 63 panels for this task

The agent must read this worksheet to determine the target panel count and calculate estimated generation.

---

## Difficulty Rationale (very_hard)

- Agent must read and interpret an energy calculation worksheet (not just extract numbers)
- Must set geographic location, configure and insert panels, AND write a technical report
- The minimum panel count (63) is derived from a calculation in the worksheet — it is not stated directly in the task description
- Report requires synthesizing calculation results (generation estimate = panels × 400W × 5.5h × 365 × 0.80)
- Three distinct workflows: location setting, panel placement, document authoring

---

## Verification Strategy

**Verifier**: `verifier.py::verify_net_zero_system_design`
**Result file**: `C:\Users\Docker\net_zero_result.json`

### Criteria

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| Location set to Austin (lat 30.10–30.60, lon −98.10 to −97.50) | 30 | Ruby shadow_info export |
| Panel delta ≥ 63 | 35 | Ruby ComponentInstance count delta |
| `System_Sizing_Report.txt` exists (>50 bytes) | 25 | File existence + size |
| Report mentions location, panels, energy figures, feasibility (bonus) | up to +10 | Regex content analysis |

**Pass threshold**: 60 / 100
**Do-nothing score**: 0

---

## Data Sources

- **Coordinates**: Real GPS for Austin, TX downtown area (30.4103°N, 97.8516°W)
- **Solar resource**: Real NREL PVWatts data for Austin — 5.50 kWh/m²/day annual GHI
- **Panel spec**: SunPower SPR-400-WHT-D, 400W — real commercial panel
- **System sizing**: Based on real solar engineering calculation methodology (PVWatts derate factor 0.80)

---

## Setup Details

`setup_task.ps1`:
1. Clears leftover files
2. Records baseline ComponentInstance count via Ruby plugin
3. Writes `energy_worksheet.txt` with real NREL data and sizing calculation
4. Relaunches SketchUp for agent

---

## Edge Cases

- Minimum panel count is 63 (partial system, per worksheet). Full net-zero would require ~343 panels — not achievable on this building model.
- If agent places exactly 63–99 panels: full panel credit
- Partial credit up to 18 pts if agent places some panels (<63)
- Report content bonus requires: location reference (lat/lon digits), panel count mention, energy/kWh terms, feasibility language
