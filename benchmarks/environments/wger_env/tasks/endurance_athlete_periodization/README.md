# endurance_athlete_periodization

## Overview

An Exercise Physiologist at the National Endurance Performance Lab sets up a full 16-week spring periodization program in wger for an elite marathon runner. The task requires reading a specification document, then performing multiple distinct operations across weight logging, measurement tracking, routine/training day management, exercise assignment, and nutrition planning.

## Occupation

**Exercise Physiologist** (SOC 29-9091.00)
Industry: Health Care and Social Assistance

## Difficulty

**very_hard** — Requires reading a companion specification document and independently performing 5 categories of interdependent operations across different sections of the wger application. The agent must discover all navigation paths, create entities in the correct order (category before entry, routine before day, day before exercise assignment), and enter precise numeric values.

## Task Requirements

The agent must read `/home/ga/Documents/marathon_periodization_plan.txt` and then:

1. **Log 8 historical body weight entries** (weekly weigh-ins Jan 6 – Feb 24, 2026) under the admin account

2. **Create 2 physiological measurement categories** and log 4 historical bi-weekly entries each:
   - "Cooper Test Distance" (unit: m) — 4 bi-weekly 12-minute run test results
   - "Resting Heart Rate" (unit: bpm) — 4 bi-weekly morning RHR readings

3. **Build the periodized training routine** named "16-Week Marathon Spring Periodization":
   - Description: "Elite marathon runner spring race preparation: Base, Build, Peak, Taper phases"
   - 6 training days across 4 phases with correct day-of-week assignments:
     - "Base Phase - Long Run" → Sunday (DOW=7)
     - "Base Phase - Easy Recovery" → Wednesday (DOW=3)
     - "Build Phase - Tempo Work" → Tuesday (DOW=2)
     - "Build Phase - Long Intervals" → Friday (DOW=5)
     - "Peak Phase - Race Pace" → Tuesday (DOW=2)
     - "Taper Phase - Shakeout" → Friday (DOW=5)
   - Exercises assigned to each day from the wger exercise database

4. **Create competition nutrition plan** named "Marathon Competition Phase - Race Week":
   - Energy: 3200 kcal
   - Protein: 145 g
   - Carbohydrates: 480 g
   - Fat: 75 g

## Scoring (100 points)

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 16 | 8 weight entries on correct dates within ±0.3 kg (2 pts each) |
| C2 | 5 | "Cooper Test Distance" category with unit "m" |
| C3 | 5 | "Resting Heart Rate" category with unit "bpm" |
| C4 | 10 | 4 correct Cooper Test entries within ±20 m |
| C5 | 10 | 4 correct Resting HR entries within ±1 bpm |
| C6 | 10 | Routine exists with correct description |
| C7 | 12 | At least 5 of 6 named training days exist (2 pts each) |
| C8 | 8 | At least 4 of 6 days have correct day-of-week assignment |
| C9 | 4 | At least 4 exercises assigned across all training days |
| C10 | 10 | "Marathon Competition Phase - Race Week" nutrition plan exists |
| C11 | 10 | Energy goal = 3200 kcal (±10) |
| C12 | 10 | At least 2 of 3 macro goals correct within ±5 g |

**Pass threshold:** 60 points

## Verification Strategy

- **C1**: Query `WeightEntry` model filtered by admin user and each of the 8 target dates
- **C2–C3**: Query `Category` model for each category name, check unit field
- **C4–C5**: Query `Entry` model via category FK, match each date, verify value within tolerance
- **C6**: Query `Routine` model by name + user, check description substring match
- **C7–C8**: Query `Day` model by routine FK, match each expected day name, check `day.day` M2M for DOW codes
- **C9**: Count `SlotEntry` objects across all slots/days of the routine
- **C10–C12**: Query `NutritionPlan` by description + user, check `goal_energy`, `goal_protein`, `goal_carbohydrates`, `goal_fat`

## Key Design Decisions

- **Companion document pattern**: All values are in `/home/ga/Documents/marathon_periodization_plan.txt`, not in the task description. Agent must read and interpret a realistic professional document.
- **Interdependent creation order**: Measurement categories must exist before entries can be logged; routine must exist before days can be added; days must exist before exercises can be assigned. This prevents simple random-order attempts.
- **Wide tolerances for measurement entries**: ±20 m for Cooper test, ±1 bpm for RHR — realistic given that the agent types values from a document.
- **Do-nothing gate**: If no weight entries, routine, measurement categories, or nutrition plan exist, score = 0.

## Setup/Cleanup

`setup_task.sh` deletes:
- Weight entries on the 8 target dates for admin
- Any existing "16-Week Marathon Spring Periodization" routine
- Any existing "Cooper Test Distance" or "Resting Heart Rate" categories
- Any existing "Marathon Competition Phase - Race Week" nutrition plan

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task definition and metadata |
| `setup_task.sh` | Pre-task: cleans state, writes spec doc, records baselines, launches Firefox |
| `export_result.sh` | Post-task: queries all entities, writes `/tmp/endurance_periodization_result.json` |
| `verifier.py` | Multi-criterion verifier: `verify_endurance_athlete_periodization` |
| `README.md` | This documentation |
