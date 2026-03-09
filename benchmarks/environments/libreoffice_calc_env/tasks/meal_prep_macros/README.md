# Meal Prep Macro Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Formulas (VLOOKUP/INDEX), arithmetic, conditional formatting, multi-constraint optimization  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Plan a week's meal prep (5 days) that hits specific macronutrient targets while working with a provided meal database. This task tests formula creation, lookup functions, conditional formatting, and practical constraint satisfaction.

## Task Description

You are helping a fitness enthusiast plan their weekly meal prep. They need 5 lunches (Monday-Friday) that collectively meet daily macro targets:

- **Protein**: 180g per day (±5g acceptable)
- **Carbohydrates**: 220g per day (±5g acceptable)  
- **Fats**: 60g per day (±5g acceptable)

You have a database of 5 meal options with their base nutritional values (per serving). Your job is to:

1. Create a meal plan table selecting meals for each day
2. Use formulas to calculate macros (accounting for portion sizes)
3. Calculate daily totals and compare to targets
4. Apply conditional formatting to highlight target achievement
5. Ensure variety and reasonable portion sizes

## Starting State

- LibreOffice Calc opens with a blank spreadsheet
- A meal database CSV file is available: `/home/ga/Documents/meal_database.csv`
- Database contains: Meal Name, Protein (g), Carbs (g), Fats (g), Cost ($)

## Meal Database

| Meal Name | Protein (g) | Carbs (g) | Fats (g) | Cost ($) |
|-----------|-------------|-----------|----------|----------|
| Chicken & Rice Bowl | 42 | 58 | 12 | 6.50 |
| Salmon & Sweet Potato | 38 | 45 | 18 | 8.75 |
| Turkey Chili | 35 | 38 | 14 | 5.25 |
| Greek Pasta Salad | 28 | 62 | 16 | 4.80 |
| Beef Stir-Fry | 45 | 42 | 22 | 7.90 |

## Required Structure

Create a meal plan table with:

**Headers** (suggested layout):
- Day (Monday-Friday)
- Meal Name
- Portion Size (multiplier, e.g., 1.0 = 1 serving)
- Protein (g) - calculated
- Carbs (g) - calculated
- Fats (g) - calculated
- Cost ($) - calculated

**Totals Row**: Sum each macro column  
**Target Row**: Show targets (180g, 220g, 60g)  
**Deviation Row**: Calculate difference from target

## Required Formulas

1. **Lookup formulas**: Use VLOOKUP or INDEX/MATCH to retrieve base macro values from meal database
2. **Portion scaling**: Multiply base values by portion size: `=VLOOKUP(...) * portion_size`
3. **Totals**: SUM formulas for each macro column
4. **Deviation**: `=total - target` for each macro

## Conditional Formatting

Apply color-coded highlighting to total/deviation cells:
- **Green**: Within ±5g of target (goal achieved)
- **Yellow**: Within ±10g but outside ±5g (acceptable)
- **Red**: More than ±10g from target (needs adjustment)

## Success Criteria

1. ✅ **Structure Complete**: Required columns and rows present
2. ✅ **Formulas Implemented**: VLOOKUP/INDEX and calculations (not hardcoded)
3. ✅ **Protein Target Met**: Total 175-185g (within ±2.8%)
4. ✅ **Carbs Target Met**: Total 215-225g (within ±2.3%)
5. ✅ **Fats Target Met**: Total 55-65g (within ±8.3%)
6. ✅ **Conditional Formatting**: Applied to total cells
7. ✅ **Realistic Portions**: All portions 0.5x-3.0x
8. ✅ **Meal Variety**: At least 3 different meals used

**Pass Threshold**: 75% (6 out of 8 criteria)

## Tips

- Import the meal database first (File → Open → meal_database.csv)
- Create your meal plan on a new sheet or below the database
- Use absolute references ($) for the database lookup range
- Adjust portion sizes iteratively to hit all three targets simultaneously
- Copy formulas down for all 5 days
- Conditional formatting: Format → Conditional → Condition (use formulas)

## Skills Tested

- CSV import
- VLOOKUP or INDEX/MATCH functions
- Relative vs. absolute cell references
- Formula copying and cell ranges
- SUM and arithmetic operations
- Conditional formatting with formula-based rules
- Multi-constraint optimization
- Practical problem-solving