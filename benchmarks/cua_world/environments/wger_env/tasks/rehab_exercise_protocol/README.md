# rehab_exercise_protocol

## Overview

A Clinical Exercise Physiologist running a hospital outpatient Phase II cardiac rehabilitation program sets up a comprehensive 12-week patient program in wger. The patient is a post-STEMI myocardial infarction survivor cleared for supervised exercise. The task requires reading a clinical protocol document and entering historical assessment data, building a rehabilitation exercise routine, and creating a heart-healthy nutrition plan.

## Occupation

**Clinical Exercise Physiologist** (SOC 29-9091.00)
Industry: Health Care and Social Assistance

## Difficulty

**very_hard** — Requires reading a clinical protocol companion document and independently performing 4 categories of interdependent data entry across body weight logging, clinical measurement tracking (3 categories, 5 entries each), exercise routine construction, and nutrition planning. The agent must navigate the wger UI without any explicit step guidance.

## Task Requirements

The agent must read `/home/ga/Documents/cardiac_rehab_protocol.txt` and then:

1. **Log 6 historical body weight entries** (weekly weigh-ins Jan 12 – Feb 16, 2026) under the admin account (tracking the patient's weight during Phase I inpatient stay)

2. **Create 3 clinical measurement categories** and log 5 historical assessment entries each:
   - "6-Minute Walk Distance" (unit: m) — functional capacity assessed every 2 weeks
   - "Resting Systolic BP" (unit: mmHg) — pre-exercise seated blood pressure
   - "Borg RPE Score" (unit: RPE) — post-exercise perceived exertion (6–20 scale)

3. **Build Phase II rehabilitation routine** named "Phase II Cardiac Rehabilitation Protocol":
   - Description: "Supervised outpatient cardiac rehab: 12-week progressive aerobic and resistance program"
   - 3 training days (Mon/Wed/Fri schedule):
     - "Aerobic Warm-Up and Walking" → Monday (DOW=1)
     - "Low-Intensity Resistance Circuit" → Wednesday (DOW=3)
     - "Active Recovery and Flexibility" → Friday (DOW=5)
   - Exercises assigned from wger database (low-intensity: Walking, Dumbbell Lateral Raise, Bicep Curl)

4. **Create heart-healthy nutrition plan** named "Cardiac Heart-Healthy Eating Plan":
   - Energy: 2100 kcal
   - Protein: 95 g
   - Carbohydrates: 280 g
   - Fat: 58 g

## Scoring (100 points)

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 12 | 6 weight entries on correct dates within ±0.3 kg (2 pts each) |
| C2 | 5 | "6-Minute Walk Distance" category with unit "m" |
| C3 | 5 | "Resting Systolic BP" category with unit "mmHg" |
| C4 | 5 | "Borg RPE Score" category with unit "RPE" |
| C5 | 10 | 5 correct 6MWD entries within ±10 m |
| C6 | 10 | 5 correct BP entries within ±2 mmHg |
| C7 | 10 | 5 correct RPE entries within ±1 |
| C8 | 10 | Routine exists with correct description |
| C9 | 9 | All 3 named training days exist (3 pts each) |
| C10 | 6 | At least 2 days have correct day-of-week assignment (3 pts each) |
| C11 | 8 | At least 2 exercises assigned across training days |
| C12 | 10 | "Cardiac Heart-Healthy Eating Plan" nutrition plan exists |
| C13 | 10 | Energy goal 2100 kcal ±10, and at least 2 of 3 macros correct ±5 g |

**Pass threshold:** 58 points

## Verification Strategy

- **C1**: Query `WeightEntry` on target dates for admin user, verify value within ±0.3 kg
- **C2–C4**: Query `Category` by name for admin user, check `unit` field
- **C5–C7**: Query `Entry` via category FK, match each of 5 dates, verify value within tolerance
- **C8**: Query `Routine` by name + user, check description substring
- **C9–C10**: Query `Day` by routine FK, match expected day names, check DOW codes in `day.day` M2M
- **C11**: Count `SlotEntry` objects across all slots in all routine days
- **C12–C13**: Query `NutritionPlan` by description + user, check goal fields

## Key Design Decisions

- **Clinical realism**: The 5 assessment entries per category reflect a real Phase II rehab protocol (bi-weekly assessments at Weeks 1, 3, 5, 7, 9). Values show realistic improvement trajectories (6MWD 310→448m, BP 148→130mmHg, RPE 14→11).
- **Soft tolerance for clinical measures**: BP checked within ±2 mmHg, RPE within ±1 — realistic rounding from manual recording.
- **Three-day/week structure**: The Mon/Wed/Fri schedule is standard in cardiac rehab (AHA guidelines) — physiologically justified, not arbitrary.
- **Do-nothing gate**: If no weight entries, routine, measurement categories, or nutrition plan exist, score = 0.

## Setup/Cleanup

`setup_task.sh` deletes:
- Weight entries on the 6 target dates for admin
- Any existing "Phase II Cardiac Rehabilitation Protocol" routine
- Any existing "6-Minute Walk Distance", "Resting Systolic BP", or "Borg RPE Score" categories
- Any existing "Cardiac Heart-Healthy Eating Plan" nutrition plan

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task definition and metadata |
| `setup_task.sh` | Pre-task: cleans state, writes clinical protocol, records baselines, launches Firefox |
| `export_result.sh` | Post-task: queries all entities, writes `/tmp/rehab_protocol_result.json` |
| `verifier.py` | Multi-criterion verifier: `verify_rehab_exercise_protocol` |
| `README.md` | This documentation |
