# Task: emergency_diversion_plan

## Domain Context

A critical in-flight emergency skill for VFR pilots is the ability to quickly
build a diversion plan to the nearest suitable alternate airport. In a real
engine-rough scenario, a pilot must:

1. Declare an emergency or advise ATC.
2. Identify the nearest airport with a suitable runway.
3. Build a direct-to diversion route in the EFB.
4. **Save the plan with an immediately recognisable name** so it can be
   referenced during the approach and shared verbally with ATC.

**Occupation context**: Private pilots (SOC 53-2011) and flight instructors
(SOC 25-1194) train for this exact scenario in emergency procedure drills.
Real-world Avare users can save plans to named files; saving as "EMER" is a
recognisable convention.

---

## Task Goal

You are airborne over the Bay Area with a rough-running engine. Your current
position fix is **KSFO** (use it as the origin waypoint). Choose **any
suitable Bay Area alternate airport** that can accept your aircraft, build a
direct flight plan from KSFO to that alternate, and save it with the filename
**EMER** (resulting file: `EMER.csv`).

Acceptable alternates: **KHAF** (Half Moon Bay), **KSQL** (San Carlos),
**KPAO** (Palo Alto), **KLVK** (Livermore), **KCCR** (Concord, now Buchanan
Field), **KWVI** (Watsonville), **KSJC** (San Jose), **KNUQ** (Moffett Field),
**KOAK** (Oakland), **KAPC** (Napa County).

> Very Hard — the agent must discover how to name a plan on save, know which
> airports qualify as Bay Area alternates, and navigate the Plan screen without
> step-by-step UI guidance.

---

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| EMER.csv exists (GATE) | — | Score=0 if not present |
| KSFO present in EMER plan | 40 | Origin waypoint |
| Accepted Bay Area alternate present | 60 | Any of the 10 listed codes |
| **Pass threshold** | **70** | Both criteria required |

> With only KSFO (40 pts), score = 40 < 70 — both sub-goals must be met.

---

## Verification Strategy

1. **export_result.sh** (Android device):
   - Takes final screenshot.
   - Force-stops Avare to flush data.
   - Checks for `EMER.csv` (case variants) in `/sdcard/avare/Plans/`.
   - Copies found file → `/sdcard/avare_emer_plan.txt`.
   - Writes `true/false` to `/sdcard/avare_emer_found.txt`.

2. **verifier.py** (`check_emergency_diversion_plan`) (host):
   - Pulls `avare_emer_found.txt` and `avare_emer_plan.txt` via `copy_from_env`.
   - **Gate**: if `emer_found == false` → score 0.
   - Checks plan text for `KSFO`.
   - Checks plan text for any of the 10 acceptable alternates.

---

## Schema / Data Reference

| File / Path | Description |
|-------------|-------------|
| `/sdcard/avare/Plans/EMER.csv` | The required plan file |
| `/sdcard/avare_emer_plan.txt` | Copy written by export script |
| `/sdcard/avare_emer_found.txt` | `true` if EMER.csv was found |

Acceptable alternates (all real FAA-registered airports in the San Francisco
Bay Area):

| ICAO | Airport | City |
|------|---------|------|
| KHAF | Half Moon Bay Airport | Half Moon Bay, CA |
| KSQL | San Carlos Airport | San Carlos, CA |
| KPAO | Palo Alto Airport | Palo Alto, CA |
| KLVK | Livermore Municipal Airport | Livermore, CA |
| KCCR | Buchanan Field Airport | Concord, CA |
| KWVI | Watsonville Municipal Airport | Watsonville, CA |
| KSJC | Norman Y. Mineta San Jose Intl | San Jose, CA |
| KNUQ | Moffett Federal Airfield | Mountain View, CA |
| KOAK | Oakland Metropolitan Airport | Oakland, CA |
| KAPC | Napa County Airport | Napa, CA |

---

## Starting State

`setup_task.sh` removes any pre-existing `EMER.csv` from `/sdcard/avare/Plans/`
so the agent must create a fresh file.

---

## Edge Cases

- If the agent saves as `EMER` (without extension) the Avare app may still
  write `EMER.csv` — export script checks common case variants.
- If the agent saves under a different name, the GATE fails with score = 0.
- If the agent chooses an alternate outside the accepted list (e.g., KSFO→KSFB
  in Orlando), the 60-pt criterion is not awarded.
