# Task: shadow_study_panel_placement

## Occupation Context

**Primary occupation**: Solar Installation Manager (school district)
**GDP relevance**: $2.28B (Skelion solar design category)
**Workflow**: Assessing a rooftop site for solar suitability, placing panels with knowledge of local shadow constraints, and producing a shadow analysis report for facilities management.

---

## Task Overview

A solar installation manager is assessing an elementary school rooftop in Denver, CO for a PV installation. After setting the correct geographic location (critical for accurate shadow calculations), they must place panels and document the expected shading impact in a report for the school district's facilities team.

The building model `Solar_Project.skp` is open in SketchUp Make 2017 with the Skelion plugin active.

---

## Goal (End State)

1. **Geographic location** set to Denver, CO — latitude 39.5870° N, longitude 104.7476° W (within ±0.40° tolerance)
2. **Minimum 40 solar panels** placed on the building roof using Skelion
3. **`Shadow_Analysis_Report.txt`** saved to `C:\Users\Docker\Desktop\` containing:
   - Site coordinates
   - Number of panels placed
   - Brief shading/solar analysis summary

---

## Reference Data

`C:\Users\Docker\Desktop\denver_solar_data.txt` — placed by setup_task.ps1

Contains real NREL PVWatts solar resource data for Denver, CO including annual GHI (5.31 kWh/m²/day), seasonal variation, and shading considerations. Agent should use this to write a realistic analysis.

---

## Difficulty Rationale (very_hard)

- Agent must set location AND insert panels AND write a text report — three distinct workflows
- Writing the report requires the agent to synthesize solar resource data from the reference file and state it accurately
- The report content requirements (coordinates, panel count, shading analysis) are not spelled out in the task description — agent must infer what a professional shadow analysis report contains
- No UI path provided for any operation

---

## Verification Strategy

**Verifier**: `verifier.py::verify_shadow_study_panel_placement`
**Result file**: `C:\Users\Docker\shadow_study_result.json`

### Criteria

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| Location set to Denver (lat 39.40–39.80, lon −105.20 to −104.60) | 30 | Ruby shadow_info export |
| Panel delta ≥ 40 | 35 | Ruby ComponentInstance count delta |
| `Shadow_Analysis_Report.txt` exists (>50 bytes) | 25 | File existence + size |
| Report contains coordinates, panel count, solar/shading keywords (bonus) | up to +10 | Regex search on report content |

**Pass threshold**: 60 / 100
**Do-nothing score**: 0

---

## Data Sources

- **Coordinates**: Real GPS coordinates for Denver, CO downtown area (39.5870°N, 104.7476°W)
- **Solar resource**: Real NREL PVWatts Annual GHI for Denver — 5.31 kWh/m²/day (published, National Renewable Energy Laboratory)
- **Shading angles**: Real sun angle data for Denver winter solstice (~27° elevation)

---

## Setup Details

`setup_task.ps1`:
1. Clears leftover output files
2. Records baseline ComponentInstance count via Ruby plugin
3. Writes `denver_solar_data.txt` with real NREL data to Desktop
4. Relaunches SketchUp for agent

---

## Edge Cases

- Report must exist AND have >50 bytes to receive base points; very small files get partial credit (10 pts)
- Bonus points for report content: keywords "shadow", "panel", site coordinate digits, solar resource terms
- Location tolerance is ±0.40° to account for agents rounding to different decimal places
