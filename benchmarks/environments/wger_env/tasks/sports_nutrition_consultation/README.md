# sports_nutrition_consultation

## Overview

A Registered Sports Dietitian (RD, CSSD) conducts a periodized nutrition consultation for an elite powerlifter preparing for the National Powerlifting Championships. The task requires reading a consultation record document and performing: body composition measurement tracking (3 categories, 3 entries each), body weight history logging, and creating two distinct periodized nutrition plans (off-season and competition) each with specific macro targets and named meal slots.

## Occupation

**Sports Dietitian** (SOC 29-1031.00)
Industry: Health Care and Social Assistance

## Difficulty

**very_hard** — Requires reading a professional consultation document and independently performing 4 categories of operations: weight history logging, body composition measurement setup and data entry, and creation of two separate nutrition plans with distinct macro profiles and named meals. Creating meals within a plan is a non-obvious sub-feature of wger. No workflow hints are provided.

## Task Requirements

The agent must read `/home/ga/Documents/sports_nutrition_consult.txt` and then:

1. **Log 8 historical body weight entries** (weekly weigh-ins Jan 5 – Feb 23, 2026) tracking the athlete's bulk/cut cycle

2. **Create 3 body composition measurement categories** and log 3 historical DEXA/force plate assessment entries each:
   - "Body Fat Percentage" (unit: %) — monthly DEXA scans
   - "Lean Body Mass" (unit: kg) — from same DEXA scans
   - "Vertical Jump Height" (unit: cm) — monthly force plate testing

3. **Create off-season nutrition plan** named "Powerlifter Off-Season Hypertrophy Phase":
   - Energy: 4200 kcal | Protein: 230 g | Carbohydrates: 520 g | Fat: 110 g
   - 6 named meals: "Pre-Workout Fuel", "Post-Workout Recovery", "Breakfast", "Lunch", "Dinner", "Evening Snack"

4. **Create competition nutrition plan** named "Powerlifter Competition Peak - Weight Cut":
   - Energy: 2800 kcal | Protein: 260 g | Carbohydrates: 280 g | Fat: 70 g
   - 4 named meals: "Morning Weigh-In Breakfast", "Pre-Attempt Snack", "Inter-Attempt Fuel", "Post-Competition Recovery"

## Scoring (100 points, capped)

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 | 16 | 8 weight entries on correct dates within ±0.3 kg (2 pts each) |
| C2 | 4 | "Body Fat Percentage" category with unit "%" |
| C3 | 4 | "Lean Body Mass" category with unit "kg" |
| C4 | 4 | "Vertical Jump Height" category with unit "cm" |
| C5 | 6 | 3 correct Body Fat % entries within ±0.2% |
| C6 | 6 | 3 correct Lean Body Mass entries within ±0.3 kg |
| C7 | 6 | 3 correct Vertical Jump entries within ±1 cm |
| C8 | 10 | Off-season plan exists |
| C9 | 10 | Off-season macros correct (≥3 of 4 within tolerance) |
| C10 | 10 | Off-season plan has ≥5 of 6 correct meals |
| C11 | 10 | Competition plan exists |
| C12 | 10 | Competition macros correct (≥3 of 4 within tolerance) |
| C13 | 8 | Competition plan has ≥3 of 4 correct meals |

**Pass threshold:** 60 points (raw total may exceed 100; capped at 100)

## Verification Strategy

- **C1**: Query `WeightEntry` on each of 8 dates for admin user, verify within ±0.3 kg
- **C2–C4**: Query `Category` by name for admin user, check `unit` field exact match
- **C5–C7**: Query `Entry` via category FK on 3 assessment dates, check value within tolerance
- **C8–C13**: Query `NutritionPlan` by description + user; check `goal_*` fields; query `Meal.objects.filter(plan=plan).values_list('name')` for meal names

## Key Design Decisions

- **Dual nutrition plan**: This is the only wger hard task that requires creating 2 separate nutrition plans with different macro profiles. Tests whether the agent understands that plans are separate entities.
- **Meal creation within plans**: The `Meal` model in wger is accessed via the plan detail page or API (`/api/v2/meal/`). This is a non-obvious wger feature not exercised in other existing hard tasks.
- **Physiologically realistic values**: BFP decreasing 18.4→17.2% over 8 weeks while LBM increasing 85.1→87.8 kg with Vertical Jump improving 58→64 cm is consistent with a powerlifter in a strength/hypertrophy block.
- **Do-nothing gate**: If no weight entries, neither nutrition plan, nor any measurement category exists, score = 0.

## Setup/Cleanup

`setup_task.sh` deletes:
- Weight entries on the 8 target dates for admin
- Any existing "Powerlifter Off-Season Hypertrophy Phase" or "Powerlifter Competition Peak - Weight Cut" nutrition plans (and their meals via cascade)
- Any existing "Body Fat Percentage", "Lean Body Mass", or "Vertical Jump Height" categories

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task definition and metadata |
| `setup_task.sh` | Pre-task: cleans state, writes consultation record, records baselines, launches Firefox |
| `export_result.sh` | Post-task: queries all entities and meals, writes `/tmp/sports_nutrition_result.json` |
| `verifier.py` | Multi-criterion verifier: `verify_sports_nutrition_consultation` |
| `README.md` | This documentation |
