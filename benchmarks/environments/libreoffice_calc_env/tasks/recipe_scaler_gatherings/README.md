# Recipe Scaler for Large Gatherings Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, proportional reasoning, conditional logic, practical rounding  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Scale a cookie recipe from 24 cookies to 75 cookies by calculating proportional ingredient amounts and applying practical rounding rules. This task tests understanding of ratios, formula application, and real-world cooking constraints.

## Task Description

The agent must:
1. Open a spreadsheet containing a recipe for 24 cookies with 8 ingredients
2. Calculate the scaling factor (75 ÷ 24 = 3.125)
3. Create formulas to scale each ingredient by this factor
4. Apply practical rounding rules (eggs must be whole numbers, rounded UP)
5. Ensure all calculations use formulas, not hardcoded values
6. Save the completed spreadsheet

## Starting Data

| Ingredient | Original Amount | Unit |
|------------|-----------------|------|
| All-Purpose Flour | 1.5 | cups |
| Granulated Sugar | 0.667 | cups |
| Butter (softened) | 0.5 | cups |
| Eggs | 2 | whole |
| Vanilla Extract | 1.5 | tsp |
| Baking Soda | 0.75 | tsp |
| Salt | 0.5 | tsp |
| Chocolate Chips | 1.5 | cups |

## Expected Results

- **Scaling Factor**: 3.125 (75/24)
- **Scaled Eggs**: 6.25 (2 × 3.125)
- **Practical Eggs**: 7 (rounded UP from 6.25)
- **Other ingredients**: Scaled proportionally with practical rounding

## Verification Criteria

1. ✅ **Scaling Factor Correct**: 3.125 calculated and used
2. ✅ **All Ingredients Scaled**: 8 ingredients with accurate scaled amounts
3. ✅ **Eggs Properly Rounded**: Eggs value is whole number (7)
4. ✅ **Formulas Present**: At least 8 formula cells detected
5. ✅ **Practical Amounts**: Values rounded to cookable measurements
6. ✅ **Structure Valid**: Proper columns and organization

**Pass Threshold**: 70% (4/6 criteria must pass)

## Skills Tested

- Proportional calculation (ratios)
- Formula creation with cell references
- Absolute cell references ($B$1)
- ROUNDUP function for whole numbers
- IF statements for conditional rounding
- Practical decision-making

## Tips

- Create clearly labeled cells for target quantity (75) and original quantity (24)
- Use absolute references for the scaling factor (e.g., =$E$1)
- Eggs MUST be whole numbers - use ROUNDUP()
- Other ingredients can be rounded to nearest 0.25 for practicality
- Ensure formulas reference cells, not hardcoded values