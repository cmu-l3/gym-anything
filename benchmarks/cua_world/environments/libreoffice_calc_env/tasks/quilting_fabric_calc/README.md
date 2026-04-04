# Quilting Fabric Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, unit conversion, percentage calculations, constraint-based math  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Calculate total fabric requirements for a quilting project by creating formulas to compute area, apply shrinkage factors, convert to yardage based on fabric width constraints, determine additional purchases needed, and calculate costs. This task tests multi-step calculations, unit conversions, and practical problem-solving with real-world constraints.

## Task Context

Maria is making a quilt and needs to verify she has enough fabric before cutting. She's already purchased some fabric but must account for:
- Pre-washing shrinkage (5%)
- Fabric width limitations (how many pieces fit across)
- Additional yardage needed beyond what's purchased
- Total cost of additional fabric needed

## Task Description

The agent must:
1. Open a partially completed spreadsheet with pattern piece data
2. Calculate area per piece (Length × Width)
3. Calculate total area needed (Area × Quantity)
4. Add 5% shrinkage factor to total area
5. Convert area to yards required (accounting for fabric width)
6. Calculate additional yardage needed (Required - Purchased, minimum 0)
7. Calculate additional cost (Additional Yards × Price per Yard)
8. Sum total additional cost

## Expected Results

**Formula Columns to Complete:**
- **Area per Piece (sq in)**: `=Length * Width`
- **Total Area (sq in)**: `=Area_per_Piece * Quantity`
- **Area with Shrinkage (sq in)**: `=Total_Area * 1.05`
- **Yards Required**: `=Area_with_Shrinkage / (Fabric_Width * 36)`
- **Additional Yards Needed**: `=MAX(0, Yards_Required - Yards_Purchased)`
- **Additional Cost**: `=Additional_Yards * Price_per_Yard`
- **Total Additional Cost**: `=SUM(Additional_Cost_Column)`

## Verification Criteria

1. ✅ **Formulas Present**: Key calculation columns contain formulas (not static values)
2. ✅ **Area Calculations Correct**: Length × Width × Quantity computed accurately
3. ✅ **Shrinkage Applied**: 5% shrinkage factor included (multiply by 1.05)
4. ✅ **Yardage Conversion Accurate**: Converts sq in to yards using fabric width
5. ✅ **Additional Needs Calculated**: Uses MAX to prevent negative yardage
6. ✅ **Costs Accurate**: Additional cost = additional yardage × price
7. ✅ **Total Sum Correct**: Total additional cost properly summed

**Pass Threshold**: 70% (5/7 criteria must pass)

## Skills Tested

- Multi-step formula creation
- Unit conversion (inches to yards)
- Percentage calculations (shrinkage)
- Constraint-based calculations (fabric width)
- MAX function for conditional logic
- SUM function for totals
- Currency formatting
- Practical problem-solving

## Starting Data

| Pattern Piece | Length | Width | Qty | Fabric Type | Width | Purchased | Price/Yd |
|--------------|--------|-------|-----|-------------|-------|-----------|----------|
| Large Square | 12.5   | 12.5  | 20  | Blue Floral | 44    | 1.5       | $12.99   |
| Small Square | 6.5    | 6.5   | 40  | Yellow Solid| 44    | 1.0       | $8.99    |
| Rectangle    | 12.5   | 6.5   | 30  | Green Print | 44    | 2.0       | $11.99   |
| Border Strip | 72.0   | 4.5   | 4   | Navy Solid  | 44    | 0.5       | $9.99    |
| Backing      | 90.0   | 90.0  | 1   | White Muslin| 108   | 0.0       | $6.99    |

## Example Calculation (Large Square)

- Area per piece: 12.5 × 12.5 = **156.25 sq in**
- Total area: 156.25 × 20 = **3,125 sq in**
- With shrinkage: 3,125 × 1.05 = **3,281.25 sq in**
- Yards required: 3,281.25 / (44 × 36) = **2.07 yards**
- Additional needed: MAX(0, 2.07 - 1.5) = **0.57 yards**
- Additional cost: 0.57 × $12.99 = **$7.40**

## Tips

- Formula columns are intentionally left empty - you must create all formulas
- Use cell references (e.g., `A2*B2`) rather than typing numbers
- Remember: 1 yard = 36 inches
- Fabric width affects layout efficiency (pieces must fit across width)
- Use MAX(0, ...) to ensure additional yardage isn't negative
- Apply currency formatting to cost columns (optional but recommended)