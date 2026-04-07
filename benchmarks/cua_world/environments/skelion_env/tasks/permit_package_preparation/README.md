# Task: permit_package_preparation

## Occupation Context

**Primary occupation**: Solar Energy Systems Engineer (permit documentation)
**GDP relevance**: $2.28B (Skelion solar design category)
**Workflow**: Preparing a code-compliant SketchUp model for submission to a municipal building department as part of a solar PV permit application. NYC DoB requires specific technical parameters and a separate permit-ready model file.

---

## Task Overview

Metro Solar Group is preparing a permit package for a commercial rooftop PV installation in New York City. The NYC Department of Buildings requires specific panel configuration (landscape orientation, 10° tilt for ballasted flat-roof systems per Local Law 77), a panel count within structural load limits (60–150), and a dedicated model file named `Permit_Ready.skp`. The engineer (agent) must configure all parameters and produce the permit-ready file.

The building model `Solar_Project.skp` is open in SketchUp Make 2017 with Skelion installed.

---

## Goal (End State)

1. **Geographic location** set to New York City, NY — latitude 40.7128° N, longitude 74.0060° W (within ±0.40° tolerance)
2. **Panel orientation**: Landscape (per NYC fire setback rules)
3. **Panel tilt**: 10 degrees (maximum for ballasted flat-roof per NYC LL 77)
4. **Panel count**: Between 60 and 150 panels (structural load limits)
5. **`Permit_Ready.skp`** saved to `C:\Users\Docker\Desktop\` via File > Save As — this is the permit submission file

---

## Reference Document

`C:\Users\Docker\Desktop\nyc_permit_requirements.txt` — placed by setup_task.ps1

Contains NYC DoB permit requirements: exact coordinates, orientation/tilt specifications, panel count range, fire department access requirements, and the file naming convention.

---

## Difficulty Rationale (very_hard)

- Five independent parameters must all be correct (location, orientation, tilt, panel count range, file save)
- Agent must discover both SketchUp's Save As workflow AND Skelion's parameter configuration
- Panel count has an UPPER bound (150) — agent must exercise judgment, not just maximize
- The Permit_Ready.skp file requires using File > Save As (not just Ctrl+S), which is a distinct UI workflow
- No UI path provided for any operation

---

## Verification Strategy

**Verifier**: `verifier.py::verify_permit_package_preparation`
**Result file**: `C:\Users\Docker\permit_package_result.json`

### Criteria

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| Location set to NYC (lat 40.50–40.90, lon −74.20 to −73.80) | 25 | Ruby shadow_info export (checks both Permit_Ready.skp and Solar_Project.skp) |
| Panel delta in [60, 150] | 35 | Ruby ComponentInstance count delta (panels placed within required range) |
| `Permit_Ready.skp` exists on Desktop (>50 KB) | 40 | File existence + minimum size (valid .skp must be >50 KB) |

**Pass threshold**: 60 / 100
**Do-nothing score**: 0

### Panel Count Edge Cases

- 60–150 panels: full 35 pts
- >150 panels: 15 pts partial (exceeds structural limit)
- 1–59 panels: proportional partial up to 15 pts
- 0 panels: 0 pts

### Permit_Ready.skp Edge Cases

- Exists and >50 KB: full 40 pts
- Exists but <50 KB: 15 pts (may be empty/corrupt save)
- Does not exist: 0 pts

---

## Export Details

`export_result.ps1` performs a dual extraction:
1. First extracts model state from `Solar_Project.skp` (the working model)
2. If `Permit_Ready.skp` exists, also extracts its model state separately via a second Ruby plugin launch
3. Uses the best available data (prefers Permit_Ready.skp if it exists)

---

## Data Sources

- **NYC coordinates**: Real GPS for NYC (40.7128°N, 74.0060°W — Manhattan)
- **NYC building code**: Based on real NYC Department of Buildings solar permit requirements, Local Law 77 (ballasted system tilt limits), FDNY fire access setback requirements
- **Panel count limits**: Based on real structural load analysis practices for commercial flat-roof buildings

---

## Edge Cases

- Agent may modify Solar_Project.skp and forget to Save As — the working model check provides partial verification
- If agent saves Permit_Ready.skp to a different location (not Desktop), it won't be found — 0 pts for file criterion
- The dual-model extraction in export_result.ps1 means the verifier sees the best state regardless of which model the agent was working in when the task ended
