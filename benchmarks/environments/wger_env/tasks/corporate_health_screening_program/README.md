# corporate_health_screening_program

## Overview

An Occupational Health Nurse (OHN) at Meridian Industrial Services enrolls 3 high-risk employees into a company wellness program following an annual biometric screening. The task requires reading an enrollment brief, registering 3 employees with exact IT-assigned credentials, building a group ergonomic exercise routine, creating a heart-healthy nutrition plan with named meal slots, and setting up measurement tracking categories for monthly check-ins.

## Occupation

**Occupational Health Nurse** (SOC 29-1141.00)
Industry: Manufacturing

## Difficulty

**very_hard** — Requires reading a companion enrollment brief and independently performing 5 distinct operations across different wger features: user registration (3 employees with exact credentials), routine + training day + exercise creation, nutrition plan creation with macro goals AND named meals, and measurement category creation. No workflow path is provided.

## Task Requirements

The agent must read `/home/ga/Documents/occ_health_enrollment_brief.txt` and then:

1. **Register 3 employees as wger users**:
   - `dwilliams_meridian` / d.williams@meridian-ind.com (Derek Williams)
   - `rparker_meridian` / r.parker@meridian-ind.com (Ruth Parker)
   - `lchavez_meridian` / l.chavez@meridian-ind.com (Luis Chavez)

2. **Create group exercise routine** named "Meridian Ergonomic Wellness Circuit":
   - Description: "12-week cardiovascular risk reduction program for sedentary manufacturing workers"
   - 3 training days:
     - "Cardio and Core Activation" → Monday (DOW=1)
     - "Upper Body Resistance" → Wednesday (DOW=3)
     - "Lower Body Mobility and Strength" → Friday (DOW=5)
   - Exercises from wger database assigned to each day

3. **Create nutrition plan** named "Meridian Metabolic Risk Reduction Plan":
   - Energy: 2200 kcal | Protein: 110 g | Carbohydrates: 270 g | Fat: 62 g
   - 5 named meals: "Whole-Grain Breakfast", "Mid-Morning Snack", "Balanced Lunch", "Pre-Workout Snack", "Heart-Healthy Dinner"

4. **Create 2 measurement tracking categories** for monthly check-ins:
   - "Waist Circumference" (unit: cm)
   - "Resting Heart Rate" (unit: bpm)

## Scoring (100 points)

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 18 | 3 employees registered with correct usernames (6 pts each) |
| C2 | 9 | 3 employees have correct email addresses (3 pts each) |
| C3 | 10 | Routine exists with correct description |
| C4 | 9 | All 3 named training days exist (3 pts each) |
| C5 | 6 | At least 2 days have correct day-of-week assignment (3 pts each) |
| C6 | 4 | At least 3 exercises assigned across training days |
| C7 | 10 | "Meridian Metabolic Risk Reduction Plan" nutrition plan exists |
| C8 | 10 | Nutrition macros correct (≥3 of 4 within tolerance) |
| C9 | 10 | At least 4 of 5 correct meals in nutrition plan |
| C10 | 7 | "Waist Circumference" category with unit "cm" |
| C11 | 7 | "Resting Heart Rate" category with unit "bpm" |

**Pass threshold:** 70 points

## Verification Strategy

- **C1–C2**: Query `User` objects by username; check `email` field case-insensitively
- **C3**: Query `Routine` by name + admin user, check description substring
- **C4–C5**: Query `Day` by routine FK, match expected day names, check DOW M2M
- **C6**: Count `SlotEntry` objects across all days
- **C7–C9**: Query `NutritionPlan` by description + user; check goal fields; query `Meal` by plan FK
- **C10–C11**: Query `Category` by name for admin user, check `unit` field

## Key Design Decisions

- **Exact credential matching**: Real OHN scenarios involve IT-provisioned accounts with specific usernames/emails. The task tests whether the agent reads and uses the exact values from the brief.
- **Meal creation alongside macros**: This tests whether the agent knows that nutrition plans in wger can have both goal fields (macros) AND meal sub-objects — two separate operations.
- **Measurement categories without data**: Unlike the other tasks, this task only creates categories (no entries), reflecting a setup-only phase before the first check-in.
- **Do-nothing gate**: If no users registered, no routine, no nutrition plan, and no categories exist, score = 0.

## Setup/Cleanup

`setup_task.sh` deletes:
- Any existing users with usernames `dwilliams_meridian`, `rparker_meridian`, `lchavez_meridian`
- Any existing "Meridian Ergonomic Wellness Circuit" routine for admin
- Any existing "Meridian Metabolic Risk Reduction Plan" nutrition plan for admin
- Any existing "Waist Circumference" or "Resting Heart Rate" categories for admin

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task definition and metadata |
| `setup_task.sh` | Pre-task: cleans state, writes enrollment brief, records baselines, launches Firefox |
| `export_result.sh` | Post-task: queries users/routine/plan/meals/categories, writes `/tmp/corp_health_result.json` |
| `verifier.py` | Multi-criterion verifier: `verify_corporate_health_screening_program` |
| `README.md` | This documentation |
