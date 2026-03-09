# Medication Schedule Optimizer Task

**Difficulty**: 🟡 Medium  
**Skills**: Time calculations, conditional logic, constraint validation, formula creation  
**Duration**: 180 seconds (3 minutes)  
**Steps**: ~15

## Objective

Help a patient optimize a complex medication schedule by creating formulas to detect timing conflicts. The spreadsheet contains medication rules (food requirements, drug interactions, minimum intervals) and a proposed schedule. Your task is to build validation formulas that identify violations of these requirements.

## Task Description

The agent must:
1. Open a spreadsheet with two sheets:
   - **Med_Rules**: Contains 6 medications with their requirements
   - **Current_Schedule**: Contains a proposed daily medication schedule
2. Create helper formulas to identify meal windows and fasting periods
3. Build validation formulas to check:
   - Food requirement compliance (with-food vs. empty-stomach)
   - Drug interaction conflicts (medications that can't be taken together)
   - Minimum interval violations (for medications taken multiple times daily)
4. Identify the 3 deliberately planted scheduling conflicts
5. Save the file with completed formulas

## Medication Rules (Sheet 1)

| Medication | Daily_Doses | Food_Requirement | Interacts_With | Min_Hours_Between |
|------------|-------------|------------------|----------------|-------------------|
| Med_A      | 1           | With food        | (none)         | N/A               |
| Med_B      | 1           | Empty stomach    | (none)         | N/A               |
| Med_C      | 2           | No requirement   | Med_D          | 6                 |
| Med_D      | 1           | With food        | Med_C          | N/A               |
| Med_E      | 2           | Empty stomach    | (none)         | 8                 |
| Med_F      | 1           | No requirement   | (none)         | N/A               |

## Meal Times

- **Breakfast**: 7:00 AM
- **Lunch**: 12:00 PM  
- **Dinner**: 6:00 PM

**Definitions:**
- "With food" = within 30 minutes before OR after a meal
- "Empty stomach" = at least 1 hour before OR at least 2 hours after any meal

## Proposed Schedule (Sheet 2)

| Time     | Medication | Meal_Window | Empty_Stomach | Food_OK | Interaction_OK | Interval_OK |
|----------|------------|-------------|---------------|---------|----------------|-------------|
| 7:00 AM  | Med_B      | [formula]   | [formula]     | [formula] | [formula]    | [formula]   |
| 8:00 AM  | Med_E (1)  | [formula]   | [formula]     | [formula] | [formula]    | [formula]   |
| 10:00 AM | Med_A      | [formula]   | [formula]     | [formula] | [formula]    | [formula]   |
| 12:00 PM | Med_C (1)  | [formula]   | [formula]     | [formula] | [formula]    | [formula]   |
| 12:00 PM | Med_D      | [formula]   | [formula]     | [formula] | [formula]    | [formula]   |
| 2:00 PM  | Med_E (2)  | [formula]   | [formula]     | [formula] | [formula]    | [formula]   |
| 6:00 PM  | Med_F      | [formula]   | [formula]     | [formula] | [formula]    | [formula]   |
| 9:00 PM  | Med_C (2)  | [formula]   | [formula]     | [formula] | [formula]    | [formula]   |

## Expected Conflicts (Agent Should Detect)

1. **Med_A at 10:00 AM** - Requires "with food" but 10 AM is empty stomach time (3 hours after breakfast, 2 hours before lunch)
2. **Med_C and Med_D at 12:00 PM** - They interact with each other and shouldn't be taken together
3. **Med_E at 8 AM and 2 PM** - Requires 8 hours between doses, but only 6 hours apart

## Expected Results

Your formulas should correctly identify:
- Column C (Meal_Window): "YES" if within 30 min of meal, "NO" otherwise
- Column D (Empty_Stomach): "YES" if in fasting window, "NO" otherwise  
- Column E (Food_OK): "CONFLICT" if food requirement violated, "OK" otherwise
- Column F (Interaction_OK): "CONFLICT" if interaction detected, "OK" otherwise
- Column G (Interval_OK): "CONFLICT" if interval too short, "OK" otherwise

## Verification Criteria

1. ✅ **Formulas Present**: Validation columns contain formulas (not manual entries)
2. ✅ **Food Conflict Detected**: Med_A at 10 AM flagged as food timing violation
3. ✅ **Interaction Conflict Detected**: Med_C and Med_D at 12 PM flagged as interaction
4. ✅ **Interval Conflict Detected**: Med_E's 6-hour gap flagged as insufficient
5. ✅ **No False Positives**: Correctly scheduled doses not flagged as conflicts
6. ✅ **Summary Accurate**: Total conflict count equals 3 with correct breakdown

**Pass Threshold**: 70% (requires at least 4 out of 6 criteria)

## Skills Tested

- Time-based calculations and comparisons
- Nested IF statements with AND/OR logic
- VLOOKUP or cell references across sheets
- Conditional logic for constraint satisfaction
- Formula debugging and validation
- Healthcare domain understanding

## Tips

- Start with meal window detection using TIME function
- Use absolute references ($) when referencing Med_Rules sheet
- VLOOKUP can retrieve medication requirements from rules sheet
- Time calculations: (A3-A2)*24 gives hours between times
- Test formulas on one row before copying down
- Use helper columns if needed for intermediate calculations