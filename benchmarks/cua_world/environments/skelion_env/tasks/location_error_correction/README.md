# Task: location_error_correction

## Occupation Context

**Primary occupation**: Solar Sales Representative and Assessor
**GDP relevance**: $2.28B (Skelion solar design category)
**Workflow**: Quality-checking a proposal model before client presentation — identifying data-entry errors that would cause incorrect solar yield calculations and correcting them before the proposal is submitted.

---

## Task Overview

A junior technician at SunBridge Energy accidentally configured the SketchUp model's geographic location as London, UK instead of Atlanta, GA for a commercial rooftop proposal. London receives ~2.9 peak sun hours/day vs. Atlanta's ~4.9 — this error would underestimate generation by ~40% and potentially cause the client to reject a viable project. The solar sales representative (agent) must identify the error, correct the location to Atlanta, GA, and place panels for the corrected site.

The building model `Solar_Project.skp` is open in SketchUp Make 2017 **with London, UK already set as the geographic location** (pre-seeded by setup_task.ps1). The Skelion plugin is active.

---

## Goal (End State)

1. **Geographic location corrected** from London, UK (lat ~51.5°N, lon ~0.1°W) **to Atlanta, GA** — latitude 33.7490° N, longitude 84.3880° W (within ±0.50° latitude, ±0.50° longitude tolerance)
2. **Minimum 50 solar panels** placed on the roof for the Atlanta site using Skelion

---

## Reference Document

`C:\Users\Docker\Desktop\location_error_report.txt` — placed by setup_task.ps1

This professional error report specifies:
- The incorrect London coordinates currently in the model
- The correct Atlanta, GA coordinates to use
- The impact of the error on solar yield calculations

---

## Difficulty Rationale (very_hard)

- Agent must diagnose an existing error (not just perform a positive action) — reads the error report and identifies what's wrong
- Must know how to view and change geographic location in SketchUp (Model Info > Geo-location or Skelion interface)
- Must place panels AFTER correcting location (order matters for correct solar modeling)
- Starting state intentionally wrong — agent must actively fix it, not just add to it
- No UI path provided for either operation

---

## Error Pre-Seeding

`setup_task.ps1` installs a one-shot Ruby startup plugin that:
1. Sets `model.shadow_info['Latitude'] = 51.5074` and `['Longitude'] = -0.1278`
2. Calls `model.save` to persist London coordinates to `Solar_Project.skp`
3. Records baseline ComponentInstance count

The plugin is removed after firing. When the agent opens the model, `shadow_info` will contain London coordinates.

---

## Verification Strategy

**Verifier**: `verifier.py::verify_location_error_correction`
**Result file**: `C:\Users\Docker\location_correction_result.json`

### Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| Location corrected to Atlanta (lat 33.50–34.00, lon −84.60 to −84.10) | 40 | Full correction |
| Location changed from London but NOT Atlanta | 15 | Partial location credit |
| Panel delta ≥ 50 | 40 | ComponentInstance count delta |
| Both location corrected AND ≥50 panels (bonus) | +20 (capped at 100) | Full task completion bonus |

**Pass threshold**: 60 / 100
**Do-nothing score**: 0 — London location is still set, no panels added → both criteria fail

---

## Do-Nothing Invariant

Since London is pre-seeded by setup:
- Location still London → 0 pts for location criterion
- No panels added → 0 pts for panel criterion
- Total: 0 pts, `passed=False` ✓

This confirms the task satisfies the do-nothing invariant.

---

## Data Sources

- **London coordinates**: Real GPS for Central London (51.5074°N, 0.1278°W) — the intentional error
- **Atlanta coordinates**: Real GPS for Atlanta, GA (33.7490°N, 84.3880°W — Peachtree Center area)
- **Solar resource comparison**: Real NREL PVWatts data (London ~2.9 kWh/m²/day, Atlanta ~4.9 kWh/m²/day)

---

## Edge Cases

- If agent changes to a non-London, non-Atlanta location: 15 pts partial credit (shows they attempted correction)
- Partial panel credit: up to 20 pts if agent places 1–49 panels (proportional)
- Bonus 20 pts only if BOTH full Atlanta location AND ≥50 panels are achieved
