# LibreOffice Calc Home Flooring Estimator Task (`flooring_estimator@1`)

## Overview

This task challenges an agent to build a practical flooring material calculator for a home renovation project. The agent must process room measurements with irregular shapes, calculate square footage, apply waste factors, handle unit conversions, and compute total material costs.

## Rationale

**Why this task is valuable:**
- **Real-World Problem-Solving:** Common homeowner challenge of material estimation
- **Complex Geometric Calculations:** Tests ability to work with irregular shapes and area calculations
- **Multi-Step Formula Logic:** Requires chaining calculations (area → waste factor → boxes → cost)
- **Practical Unit Conversion:** Real-world mixing of measurements and box quantities
- **Error Prevention Context:** Under-ordering means delays; over-ordering wastes money

**Difficulty**: 🟡 Medium  
**Skills**: Multi-step formulas, percentage calculations, rounding functions, cost calculations  
**Duration**: 180 seconds (3 minutes)  
**Steps**: ~15

## Task Description

You're planning to install laminate flooring in three rooms:

### Room Measurements:
- **Living Room** (L-shaped): 15 ft × 12 ft + 6 ft × 4 ft alcove = **204 sq ft**
- **Bedroom** (rectangular): 12 ft × 11 ft = **132 sq ft**
- **Hallway** (rectangular): 18 ft × 3.5 ft = **63 sq ft**

### Material Specifications:
- **Laminate flooring**: $2.89 per square foot
- **Flooring boxes**: Each box covers 20 square feet
- **Underlayment**: $0.45 per square foot

### Waste Factors (industry standard):
- **Irregular shapes** (L-shaped rooms): Add 15% extra material
- **Rectangular rooms**: Add 10% extra material
- **Underlayment**: No waste factor needed (rolls fit exactly)

## Required Calculations

Create a spreadsheet that calculates:

1. **Adjusted square footage** for each room (base area + waste factor)
   - Living Room: 204 × 1.15 = 234.6 sq ft
   - Bedroom: 132 × 1.10 = 145.2 sq ft
   - Hallway: 63 × 1.10 = 69.3 sq ft

2. **Number of flooring boxes** needed (must round UP to whole boxes)
   - Living Room: CEILING(234.6 / 20) = 12 boxes
   - Bedroom: CEILING(145.2 / 20) = 8 boxes
   - Hallway: CEILING(69.3 / 20) = 4 boxes

3. **Cost of flooring** for each room (adjusted sq ft × $2.89)
   - Living Room: 234.6 × $2.89 = ~$678
   - Bedroom: 145.2 × $2.89 = ~$420
   - Hallway: 69.3 × $2.89 = ~$200

4. **Cost of underlayment** for each room (base sq ft × $0.45)
   - Living Room: 204 × $0.45 = $91.80
   - Bedroom: 132 × $0.45 = $59.40
   - Hallway: 63 × $0.45 = $28.35

5. **Total project cost**: ~$1,477.45

## Success Criteria

1. ✅ **Correct Waste Factor Application** (15% for L-shaped, 10% for rectangular)
2. ✅ **Box Rounding Logic** (uses CEILING/ROUNDUP, no fractional boxes)
3. ✅ **Accurate Cost Calculations** (flooring uses adjusted sq ft, underlayment uses base sq ft)
4. ✅ **Proper Formula Usage** (formulas used, not hard-coded values)
5. ✅ **Total Accuracy** (grand total within ±$5 of expected $1,477.45)

**Pass Threshold**: 75% (requires at least 4 out of 5 criteria)

## Skills Tested

- Multi-step formula construction
- Percentage application (waste factors)
- Rounding functions (CEILING/ROUNDUP)
- Cell referencing (absolute and relative)
- Currency calculations
- SUM functions for totals

## Tips

- Organize data in columns: Room Name, Base Sq Ft, Waste Factor, Adjusted Sq Ft, Boxes, Costs
- Use formulas like `=B2*(1+C2)` for adjusted square footage
- Use `=CEILING(D2/20)` or `=ROUNDUP(D2/20,0)` for box quantities
- Apply currency formatting to cost columns
- Use SUM functions for totals row