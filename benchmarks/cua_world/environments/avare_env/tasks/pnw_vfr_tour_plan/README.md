# Task: pnw_vfr_tour_plan

## Domain Context

Flight instructors and tour pilots planning multi-day VFR cross-country trips
need to build a complete route that visits multiple airports, filed under a
memorable plan name. The Pacific Northwest corridor from Seattle south through
Portland, Eugene, and Medford is a classic VFR training route, exposing student
pilots to Class B airspace (KSEA), Class C (KPDX), and uncontrolled (KEUG,
KMFR) environments.

**Occupation context**: Flight instructors (SOC 25-1194) and VFR tour pilots
plan multi-stop itineraries in Avare before briefing students. Using a named
plan (`PNW_TOUR`) makes it easy to reload on each leg. VFR Sectional charts are
the required display for this type of training flight.

---

## Task Goal

1. **Switch Avare to VFR Sectional chart** display (the standard for VFR
   training flights).
2. **Build and save a flight plan named `PNW_TOUR`** (file: `PNW_TOUR.csv`)
   that includes all four of the following airports:
   - **KSEA** — Seattle-Tacoma International
   - **KPDX** — Portland International
   - **KEUG** — Eugene Airport (Mahlon Sweet Field)
   - **KMFR** — Rogue Valley International–Medford

> Very Hard — the agent must discover the Plan screen, save with a custom
> name, switch the chart type, and add all 4 waypoints without step-by-step
> guidance.

---

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| PNW_TOUR.csv exists (GATE) | — | Score=0 if not present |
| Chart = Sectional (VFR) | 25 | SharedPreferences check |
| KSEA in PNW_TOUR plan | 25 | Northernmost stop |
| KPDX in PNW_TOUR plan | 20 | Portland stop |
| KEUG in PNW_TOUR plan | 15 | Eugene stop |
| KMFR in PNW_TOUR plan | 15 | Medford stop |
| **Pass threshold** | **76** | All 4 airports = 75; chart also required |

> Threshold 76 means all four airports alone (75 pts) is not sufficient —
> the Sectional chart switch is also required to pass.

---

## Verification Strategy

1. **export_result.sh** (Android device):
   - Takes final screenshot.
   - Force-stops Avare.
   - Copies SharedPreferences XML → `/sdcard/avare_pnw_prefs.xml`.
   - Checks for `PNW_TOUR.csv` → copies to `/sdcard/avare_pnw_tour_plan.txt`.
   - Writes `true/false` → `/sdcard/avare_pnw_found.txt`.

2. **verifier.py** (`check_pnw_vfr_tour_plan`) (host):
   - **Gate**: `pnw_found == false` → score 0.
   - Parses SharedPreferences for Sectional chart preference.
   - Checks `PNW_TOUR.csv` content for `KSEA`, `KPDX`, `KEUG`, `KMFR`.

---

## Schema / Data Reference

| File / Path | Description |
|-------------|-------------|
| `/sdcard/avare/Plans/PNW_TOUR.csv` | The required named plan file |
| `/sdcard/avare_pnw_tour_plan.txt` | Copy written by export script |
| `/sdcard/avare_pnw_prefs.xml` | SharedPreferences copy |
| `/sdcard/avare_pnw_found.txt` | `true` if PNW_TOUR.csv was found |

Real airports:

| ICAO | Airport | City | Class |
|------|---------|------|-------|
| KSEA | Seattle-Tacoma International | SeaTac, WA | B |
| KPDX | Portland International | Portland, OR | C |
| KEUG | Mahlon Sweet Field / Eugene Airport | Eugene, OR | C |
| KMFR | Rogue Valley International–Medford | Medford, OR | D |

---

## Starting State

`setup_task.sh` removes any existing `PNW_TOUR.csv` and attempts to set the
chart to IFR Low in SharedPreferences, so the agent must explicitly switch
back to Sectional.

---

## Edge Cases

- If the agent names the plan `PNW_TOUR` (Avare appends `.csv` automatically),
  the export script finds it.
- If the agent names it differently (e.g., `PNWTOUR`), the GATE fails.
- If the chart key is absent from SharedPreferences (never set), Avare defaults
  to Sectional; verifier awards the 25 pts.
