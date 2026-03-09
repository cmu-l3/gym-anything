# Recipe Scaling Task

**Difficulty**: 🟢 Easy  
**Skills**: Formulas, proportional calculations, absolute/relative references  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Scale a chocolate chip cookie recipe from 24 cookies to 60 cookies using formulas. Calculate a scaling factor and apply it consistently to all ingredients using proper cell references. This task tests understanding of proportional calculations, formula creation, and cell reference types (absolute vs. relative).

## Scenario

A home baker found a delicious chocolate chip cookie recipe that yields 24 cookies, but they committed to bringing 60 cookies to a school bake sale tomorrow. They need to quickly calculate the adjusted ingredient amounts.

## Task Description

The agent must:
1. Open a pre-populated spreadsheet with recipe data
2. Calculate the scaling factor in cell B4: =B2/B1 (target ÷ original)
3. Create scaled amount formulas in column D for each ingredient
4. Use absolute reference ($B$4) for scaling factor and relative reference (B7, B8, etc.) for amounts
5. Copy formula down to all ingredient rows
6. Save the file

## Starting Data

**Recipe Parameters:**
- Original Yield (B1): 24 cookies
- Target Yield (B2): 60 cookies
- Scaling Factor (B4): [empty - agent fills this]

**Ingredients (A7-C15):**
| Ingredient | Original Amount | Unit |
|------------|----------------|------|
| All-Purpose Flour | 2 | cups |
| Granulated Sugar | 1.5 | cups |
| Brown Sugar | 0.75 | cups |
| Butter | 8 | oz |
| Eggs | 2 | whole |
| Vanilla Extract | 2 | tsp |
| Baking Soda | 1 | tsp |
| Salt | 0.5 | tsp |
| Chocolate Chips | 12 | oz |

## Expected Results

- **B4**: Formula `=B2/B1` showing value 2.5
- **D7-D15**: Formulas like `=B7*$B$4`, `=B8*$B$4`, etc.
- **Scaled amounts**: Each original amount multiplied by 2.5
  - Example: 2 cups flour → 5 cups flour
  - Example: 1.5 cups sugar → 3.75 cups sugar

## Verification Criteria

1. ✅ **Scaling Factor Formula**: B4 contains `=B2/B1` and shows ~2.5
2. ✅ **Formula Pattern Correct**: Column D formulas use absolute reference ($B$4) and relative row references
3. ✅ **All Ingredients Scaled**: At least 8 ingredient rows have formulas in column D
4. ✅ **Calculations Accurate**: All scaled amounts equal original × 2.5 (±0.01 tolerance)

**Pass Threshold**: 70% (3/4 criteria must pass)

## Skills Tested

- Formula creation with = operator
- Division and multiplication operations
- Absolute cell references ($B$4)
- Relative cell references (B7, B8, etc.)
- Formula copying (fill-down)
- Proportional reasoning
- Practical mathematics

## Tips

- Absolute reference ($B$4) stays fixed when copying formulas
- Relative reference (B7) adjusts automatically when copying (B8, B9, etc.)
- Use Ctrl+D to fill down formulas, or drag the fill handle
- Check the formula bar to verify formulas (not just values)
- All ingredients should be scaled by the same factor for the recipe to work

## Common Mistakes

- Hard-coding values (typing "5" instead of "=2*2.5")
- Using relative reference for scaling factor (B4 instead of $B$4)
- Forgetting the = sign to start formulas
- Not copying formula to all ingredient rows
- Using wrong operator (+ instead of *)