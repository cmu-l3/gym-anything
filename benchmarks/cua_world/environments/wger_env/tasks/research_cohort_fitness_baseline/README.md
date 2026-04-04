# research_cohort_fitness_baseline

## Overview

A Clinical Research Scientist serving as study coordinator for the STRIDE-26 longitudinal fitness study enters baseline assessment data for 4 participants into wger. Following the initial assessment battery, the coordinator must register all participants, create standardized fitness measurement categories, log each participant's baseline assessment values, build the standardized exercise intervention routine, and set up the dietary reference nutrition plan with named meal slots.

## Occupation

**Clinical Research Scientist** (SOC 19-1042.00)
Industry: Scientific Research and Development Services

## Difficulty

**very_hard** — The most complex of the new tasks. Requires reading a multi-section research data sheet and independently performing 5 categories of operations: registering 4 participants with study-assigned credentials, creating 3 measurement categories with correct units, logging 4 baseline data points per category (12 total entries), building a 3-day exercise protocol with exercises, and creating a standardized nutrition plan with 4 named meal slots. No workflow guidance is provided.

## Task Requirements

The agent must read `/home/ga/Documents/stride26_baseline_data.txt` and then:

1. **Register 4 research participants as wger users**:
   - `stride26_p001` / participant001@stride26study.org (Helena Marsh)
   - `stride26_p002` / participant002@stride26study.org (Darnell Okonkwo)
   - `stride26_p003` / participant003@stride26study.org (Fiona Tran)
   - `stride26_p004` / participant004@stride26study.org (Marcus Delacroix)

2. **Create 3 standardized fitness assessment categories** and log 1 baseline entry per participant (4 entries per category, on each participant's assessment date):
   - "VO2max Estimate" (unit: ml/kg/min) — non-exercise prediction protocol
     - 2026-02-02: 34.2 | 2026-02-03: 41.8 | 2026-02-04: 28.9 | 2026-02-05: 38.5
   - "Handgrip Strength" (unit: kg) — Jamar dynamometer, dominant hand
     - 2026-02-02: 32.4 | 2026-02-03: 38.1 | 2026-02-04: 29.6 | 2026-02-05: 35.8
   - "Single-Leg Balance Time" (unit: s) — unipedal stance, dominant leg, eyes open
     - 2026-02-02: 18 | 2026-02-03: 24 | 2026-02-04: 12 | 2026-02-05: 21

3. **Build the STRIDE-26 exercise intervention routine** named "STRIDE-26 Standardized Exercise Intervention":
   - Description: "52-week workplace fitness RCT: progressive moderate-intensity aerobic and functional strength protocol"
   - 3 training days:
     - "Aerobic Conditioning" → Tuesday (DOW=2)
     - "Functional Strength Training" → Thursday (DOW=4)
     - "Active Mobility Session" → Saturday (DOW=6)
   - Exercises assigned from wger database (Cycling, Running, Squats, Lunges, Walking)

4. **Create standardized dietary reference plan** named "STRIDE-26 Standardized Dietary Reference":
   - Energy: 2400 kcal | Protein: 120 g | Carbohydrates: 310 g | Fat: 72 g
   - 4 standardized meal slots: "Standardized Breakfast", "Standardized Lunch", "Standardized Dinner", "Post-Exercise Recovery"

## Scoring (100 points)

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 20 | 4 participants registered with correct usernames (5 pts each) |
| C2 | 8 | 4 participants have correct email addresses (2 pts each) |
| C3 | 4 | "VO2max Estimate" category with unit "ml/kg/min" |
| C4 | 4 | "Handgrip Strength" category with unit "kg" |
| C5 | 4 | "Single-Leg Balance Time" category with unit "s" |
| C6 | 8 | 4 correct VO2max entries within ±0.5 ml/kg/min |
| C7 | 8 | 4 correct Handgrip entries within ±0.5 kg |
| C8 | 8 | 4 correct Balance entries within ±1 s |
| C9 | 10 | Routine exists with correct description |
| C10 | 9 | All 3 named training days exist (3 pts each) |
| C11 | 6 | At least 2 days have correct day-of-week assignment (3 pts each) |
| C12 | 3 | At least 3 exercises assigned across all training days |
| C13 | 8 | Nutrition plan exists with ≥3 of 4 macros correct within tolerance |
| C14 | 8 | All 4 meal slots created in nutrition plan |

**Pass threshold:** 70 points

## Verification Strategy

- **C1–C2**: Query `User` objects by each username; check `email` field
- **C3–C5**: Query `Category` by name for admin user, check `unit` field
- **C6–C8**: Query `Entry` via category FK, match each of 4 assessment dates, verify value within tolerance
- **C9**: Query `Routine` by name + admin user, check description substring
- **C10–C11**: Query `Day` by routine FK, match expected day names, check DOW codes
- **C12**: Count `SlotEntry` objects across all days
- **C13–C14**: Query `NutritionPlan` by description + user; check `goal_*` fields; query `Meal` by plan FK

## Key Design Decisions

- **One entry per participant per category**: Unlike Tasks 1 & 2 (which have multiple entries per date for one subject), this task has 4 separate dates (one per participant). The agent must understand that measurement entries belong to a category, not a user — so all 4 entries go under the admin's category.
- **Research context**: The specific dates (Feb 2–5) represent consecutive-day assessment sessions typical of a baseline visit battery in human subjects research.
- **Maximum feature breadth**: This task uniquely combines user_registration + measurement_categories + measurement_entries + routine + exercises + nutrition + meals — the broadest feature set of any wger task.
- **Do-nothing gate**: If no participants registered, no routine, no measurement categories, and no nutrition plan exist, score = 0.

## Setup/Cleanup

`setup_task.sh` deletes:
- Any existing users: `stride26_p001` through `stride26_p004`
- Any existing "STRIDE-26 Standardized Exercise Intervention" routine for admin
- Any existing "VO2max Estimate", "Handgrip Strength", or "Single-Leg Balance Time" categories
- Any existing "STRIDE-26 Standardized Dietary Reference" nutrition plan

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task definition and metadata |
| `setup_task.sh` | Pre-task: cleans state, writes baseline data sheet, records baselines, launches Firefox |
| `export_result.sh` | Post-task: queries all entities + meals, writes `/tmp/research_cohort_result.json` |
| `verifier.py` | Multi-criterion verifier: `verify_research_cohort_fitness_baseline` |
| `README.md` | This documentation |
