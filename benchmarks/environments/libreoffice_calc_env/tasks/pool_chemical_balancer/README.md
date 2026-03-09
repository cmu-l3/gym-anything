# Swimming Pool Chemical Balancing Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, complex formulas, conditional logic, lookup tables  
**Duration**: 240 seconds (4 minutes)  
**Steps**: ~15

## Objective

Process raw water test results from a residential swimming pool and calculate precise chemical adjustments needed to balance the water chemistry. This task tests data cleaning, multi-step formula creation, conditional logic, and real-world problem solving under time pressure.

## Scenario

It's Memorial Day weekend Saturday morning—your neighborhood pool's opening day. The water testing service sent messy results with mixed formats, text notes, and typos. The pool company wants $400 to balance the chemicals, but you need to do it yourself. Calculate exactly what chemicals to add before families arrive tomorrow.

## Task Description

The agent must:
1. **Clean messy test data** - Remove text notes, standardize units, fix typos
2. **Calculate deviations** from target ranges for each parameter
3. **Apply chemical dosing formulas** based on 25,000-gallon pool volume
4. **Determine urgency flags** (CRITICAL/URGENT/ROUTINE) using conditional logic
5. **Calculate total cost** and compare to the $400 professional quote
6. **Prioritize chemicals** (pH first, then chlorine, then others)

## Starting Data

**Pool Test Results (messy):**
- pH: "7.9" (slightly high - target: 7.2-7.6)
- Chlorine: "0.3 ppm" (CRITICAL - target: 1.0-3.0 ppm)
- Alkalinity: "60" (low - target: 80-120 ppm)
- Calcium Hardness: "180 ppm" (target: 200-400 ppm)
- Water Temperature: 78°F
- Mixed formats, text notes, some typos

**Chemical Dosing Reference Table provided**

## Expected Results

After proper calculations for the 25,000-gallon pool:

- **Acid needed**: ~20 oz (to lower pH from 7.9 to 7.4)
- **Chlorine needed**: ~0.62 lbs (to raise from 0.3 to 2.0 ppm, temp-adjusted)
- **Baking soda needed**: ~6.67 lbs (to raise alkalinity from 60 to 100 ppm)
- **Calcium chloride needed**: ~14.58 lbs (to raise hardness from 180 to 250 ppm)
- **Urgency flags**: Chlorine=CRITICAL, pH=URGENT, others=URGENT
- **Priority order**: pH adjusters first, then chlorine, then alkalinity, then calcium
- **Total cost**: Calculate from reference prices

## Verification Criteria

1. ✅ **Data Cleaned**: Numeric cells contain only numbers (>95% clean)
2. ✅ **pH Calculation Correct**: Acid dosing within ±2 oz of 20 oz
3. ✅ **Chlorine Calculation Correct**: Within ±0.05 lbs of 0.62 lbs
4. ✅ **Alkalinity Calculation Correct**: Within ±0.5 lbs of 6.67 lbs
5. ✅ **Urgency Flags Accurate**: Chlorine flagged as CRITICAL
6. ✅ **Chemical Priority Correct**: pH adjustments before chlorine
7. ✅ **Total Cost Calculated**: Sum of chemical costs present (±$2)
8. ✅ **Formula-Based**: At least 3 cells use formulas (not hardcoded)

**Pass Threshold**: 75% (6/8 criteria)

## Skills Tested

### Data Cleaning
- Remove text notes from cells ("7.9 (slightly high)" → 7.9)
- Standardize units (convert percentages to ppm)
- Fix typos ("73." → 7.3)
- Extract numeric values from mixed content

### Formula Skills
- Complex nested formulas (IF, AND, VLOOKUP)
- Absolute vs relative references ($)
- Named ranges for readability
- Multi-step calculation chains

### Pool Chemistry Knowledge
- pH adjustment: `(Current - Target) × Volume ÷ 10000 × Factor`
- Chlorine with temp correction: `(Target - Current) × Volume ÷ 75000 × TempFactor`
- Alkalinity: `(Target - Current) × Volume ÷ 150000`
- Calcium hardness: `(Target - Current) × Volume ÷ 120000`

### Conditional Logic
- CRITICAL: pH < 6.8 or > 8.2, Chlorine < 0.5 ppm
- URGENT: Outside normal range but not critical
- ROUTINE: Within acceptable range

## Chemical Formulas Reference
