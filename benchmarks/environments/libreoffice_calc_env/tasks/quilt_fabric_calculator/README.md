# Quilting Fabric Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, conditional logic, unit conversion, rounding  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Create a fabric quantity calculator for a quilting project by completing a partially-filled spreadsheet with formulas that calculate exact yardage requirements. The agent must account for directional patterns, fabric width constraints, and industry-standard safety margins.

## Task Description

The agent must:
1. Open a pre-populated LibreOffice Calc spreadsheet with fabric requirements
2. Add formulas to calculate total square inches needed (blocks × width × height)
3. Calculate raw yards needed, accounting for 42" usable fabric width
4. Apply conditional logic for directional vs. non-directional fabrics
5. Add 10% safety margin for shrinkage and cutting errors
6. Round up to nearest 1/8 yard (0.125) for retail purchase quantities
7. Save the completed spreadsheet

## Spreadsheet Structure

**Input Columns (pre-filled):**
- **A**: Fabric Color/Pattern name
- **B**: Number of blocks needed
- **C**: Block width (inches)
- **D**: Block height (inches)
- **E**: Is Directional? (YES/NO)

**Output Columns (formulas to add):**
- **F**: Total Square Inches Needed
- **G**: Yards Needed (Raw)
- **H**: Yards with Safety Margin
- **I**: Yards to Purchase (rounded)

## Sample Data

| Fabric | Blocks | Width | Height | Directional? | Sq In | Raw Yards | +Safety | To Buy |
|--------|--------|-------|--------|--------------|-------|-----------|---------|--------|
| Blue   | 12     | 8     | 8      | NO           | ?     | ?         | ?       | ?      |
| Red    | 8      | 10    | 6      | YES          | ?     | ?         | ?       | ?      |

## Formula Requirements

### Column F: Total Square Inches
- Formula: `=B2*C2*D2` (blocks × width × height)
- Apply to all fabric rows

### Column G: Raw Yards Needed
- **Non-directional fabrics**: `=F2/1512` (total sq in ÷ 42" width ÷ 36"/yard)
- **Directional fabrics**: `=B2*D2/36` (blocks × height ÷ 36"/yard)
- Recommended: Use IF statement: `=IF(E2="YES", B2*D2/36, F2/1512)`

### Column H: Safety Margin (10% extra)
- Formula: `=G2*1.10` or `=G2*1.1`

### Column I: Yards to Purchase
- Formula: `=CEILING(H2, 0.125)` (round up to 1/8 yard increments)
- Alternative: `=ROUNDUP(H2/0.125, 0)*0.125`

## Expected Results

- **All formulas reference cells** (not hardcoded values)
- **Directional fabrics have higher yardage** than equivalent non-directional
- **Purchase quantities are multiples of 0.125** (1/8 yard)
- **Increasing values**: Raw Yards < Safety Margin < To Purchase

## Verification Criteria

1. ✅ **Square Inches Formulas Correct**: Column F multiplies B×C×D
2. ✅ **Conditional Yards Logic**: Column G handles directional vs. non-directional
3. ✅ **Safety Margin Applied**: Column H is ~110% of Column G
4. ✅ **Proper Rounding**: Column I rounds up to 0.125 increments
5. ✅ **Values Accurate**: Calculated values match expected results
6. ✅ **Directional Premium**: Directional fabrics have higher yardage

**Pass Threshold**: 75% (4/6 criteria must pass)

## Skills Tested

- Multi-step formula chains
- Conditional logic (IF statements)
- Unit conversion (inches to yards)
- Percentage calculations (10% safety margin)
- Advanced rounding (CEILING, ROUNDUP)
- Absolute vs. relative cell references
- Real-world constraint application

## Real-World Context

**Problem**: Quilters need to buy exact fabric amounts. Too little means running out mid-project; too much wastes money on expensive specialty fabrics.

**Complications**:
- Directional patterns (stripes, text) can't be rotated, creating more waste
- Fabric sold in 1/8 yard increments at stores
- Need 10% extra for shrinkage and cutting mistakes
- Standard quilting fabric is 42-44" wide (usable width after selvage removal)

## Tips

- Start with Column F (simplest: just multiplication)
- Column G is the most complex (requires IF for directional logic)
- Use CEILING function for rounding up to specific increments
- Verify directional fabrics have higher yardage than non-directional
- Test formulas on first row, then copy down to other rows