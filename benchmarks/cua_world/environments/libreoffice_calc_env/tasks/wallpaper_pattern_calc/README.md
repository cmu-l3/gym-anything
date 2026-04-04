# Wallpaper Pattern Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Complex formulas, mathematical logic, multi-step calculations  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Build a practical wallpaper quantity calculator that accounts for pattern repeats—a real frustration for DIY home improvers. Calculate how many rolls to purchase for an accent wall, considering pattern matching waste, door cutouts, and installation contingency.

## Task Description

A homeowner is preparing to wallpaper their dining room accent wall. Wallpaper with repeating patterns requires careful calculation to avoid expensive mistakes (rolls cost $50-150 each). Buying too little risks mismatched dye lots; buying too much wastes money.

The agent must:
1. Review pre-filled wall dimensions and wallpaper specifications
2. Create formulas to calculate usable strips per roll (accounting for pattern waste)
3. Calculate total strips needed for the wall (accounting for door opening)
4. Calculate rolls needed with 10% contingency for installation errors
5. Save the completed calculator

## Starting State

LibreOffice Calc opens with a structured spreadsheet containing:
- **Wall Dimensions**: Height (108"), Width (144"), Door Width (36")
- **Wallpaper Specifications**: Roll Width (20.5"), Roll Length (396"), Pattern Repeat (21")
- **Calculations Section**: Empty cells where formulas should be added
- **Final Result Section**: Empty cell for final roll count

## Required Formulas

### Calculation Section (agent must create these):

1. **Pattern repeats per roll** (around row 10):
   - Formula: `=FLOOR(B7/B8)` or equivalent
   - Calculates how many complete pattern repeats fit in roll length

2. **Usable length per strip** (next row):
   - Formula: `=B10*B8` (if B10 has repeats per roll)
   - Each strip must align to pattern repeat

3. **Strips per roll** (next row):
   - Formula: `=FLOOR(B11/B2)` (if B11 has usable length)
   - How many wall-height strips can be cut from one roll

4. **Net wall width** (around row 14):
   - Formula: `=B3-B4`
   - Wall width minus door opening

5. **Strips needed** (next row):
   - Formula: `=ROUNDUP(B14/B6,0)` or `=CEILING(B14/B6,1)`
   - Total strips to cover the wall

6. **Rolls before contingency** (around row 17):
   - Formula: `=ROUNDUP(B15/B12,0)` or `=CEILING(B15/B12,1)`
   - Raw roll count needed

7. **Final rolls with contingency** (around row 19-20):
   - Formula: `=ROUNDUP(B18*1.1,0)` or `=CEILING(B18*1.1,1)`
   - Add 10% safety margin for mistakes/repairs

## Expected Results (with given inputs)

- Pattern repeats per roll: **18**
- Usable length per strip: **378 inches**
- Strips per roll: **3**
- Net wall width: **108 inches**
- Strips needed: **6**
- Rolls before contingency: **2**
- **Final rolls to purchase: 3**

## Success Criteria

1. ✅ **Inputs Present**: All wall and wallpaper specifications entered
2. ✅ **Formulas Used**: Calculation cells contain formulas (not hardcoded values)
3. ✅ **Strips Per Roll Correct**: Properly calculates strips per roll (≈3)
4. ✅ **Final Result Accurate**: Final roll count is 3 (±1 tolerance for different approaches)
5. ✅ **Contingency Applied**: Final calculation includes ~10% safety margin

**Pass Threshold**: 70% (3.5 out of 5 criteria)

## Skills Tested

- Complex formula creation with nested functions
- Understanding of ROUNDUP, CEILING, FLOOR functions
- Multi-step dependent calculations
- Cell referencing across sections
- Real-world mathematical problem solving
- Logical thinking about material constraints

## Tips

- Work systematically from top to bottom
- Each calculation builds on previous results
- Use FLOOR for "how many fit" calculations
- Use ROUNDUP/CEILING for "how many needed" calculations
- The pattern repeat creates waste—strips must align
- Add labels in column A for clarity
- Verify intermediate results make logical sense

## Real-World Context

This calculator mirrors actual DIY scenarios where:
- Pattern books provide minimal guidance
- Mistakes cost $50-150 per roll
- Reordering later may result in dye lot mismatch
- Installation waste happens (10% contingency is standard)
- Door/window cutouts complicate simple area calculations