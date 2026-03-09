# LibreOffice Calc Road Trip Planner Task (`road_trip_planner@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Formulas, cumulative calculations, absolute references, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Create a structured road trip itinerary spreadsheet that calculates cumulative distances, estimates fuel costs, determines daily driving times, and validates safe driving limits. This simulates real-world travel planning where you need to transform route data into an actionable budget-aware travel plan.

## Scenario

A family is planning a 5-day road trip through the southern United States. They need to know:
- How far they'll travel each day and cumulatively
- How much fuel they'll need and what it will cost
- How many hours they'll spend driving daily
- Whether any day exceeds safe driving limits (8 hours)

## Starting State

- LibreOffice Calc opens with a template file: `road_trip_template.ods`
- Template contains:
  - Column headers (Day, From → To, Distance, etc.)
  - Reference values: Gas Price ($3.45/gal), Vehicle MPG (28), Avg Speed (60 mph)
  - Empty rows for route data entry

## Route Data to Enter

| Day | From → To | Distance (mi) |
|-----|-----------|---------------|
| 1 | Home → Nashville | 420 |
| 2 | Nashville → Memphis | 210 |
| 3 | Memphis → Little Rock | 135 |
| 4 | Little Rock → Dallas | 315 |
| 5 | Dallas → Austin | 195 |

## Required Actions

### 1. Enter Route Data (Rows 2-6)
- Column A: Days 1-5
- Column B: Route segments (e.g., "Home → Nashville")
- Column C: Distances in miles

### 2. Create Cumulative Distance Formulas (Column D)
- D2: `=C2` (first day)
- D3: `=D2+C3` (adds previous cumulative + current distance)
- D4-D6: Continue the pattern

### 3. Calculate Fuel Needed (Column E)
- E2: `=C2/$J$3` (distance ÷ MPG, use absolute reference for MPG)
- Copy formula to E3:E6

### 4. Calculate Fuel Cost (Column F)
- F2: `=E2*$J$2` (gallons × price per gallon)
- Copy formula to F3:F6
- Apply currency formatting

### 5. Calculate Driving Time (Column G)
- G2: `=C2/$J$4` (distance ÷ average speed)
- Copy formula to G3:G6
- Format with 1 decimal place

### 6. Add Totals Row (Row 7)
- A7: "TOTALS"
- D7: `=D6` (final cumulative distance)
- E7: `=SUM(E2:E6)` (total gallons)
- F7: `=SUM(F2:F6)` (total fuel cost)
- G7: `=SUM(G2:G6)` (total driving hours)

### 7. Apply Conditional Formatting
- Select G2:G6 (driving time column)
- Format → Conditional Formatting → Condition
- Rule: Cell value > 8
- Format: Background color RED or ORANGE
- Purpose: Highlight unsafe driving days (>8 hours)

## Expected Results

| Day | Route | Distance | Cumulative | Fuel (gal) | Cost ($) | Time (hrs) |
|-----|-------|----------|------------|------------|----------|------------|
| 1 | Home → Nashville | 420 | 420 | 15.00 | $51.75 | 7.0 |
| 2 | Nashville → Memphis | 210 | 630 | 7.50 | $25.88 | 3.5 |
| 3 | Memphis → Little Rock | 135 | 765 | 4.82 | $16.64 | 2.25 |
| 4 | Little Rock → Dallas | 315 | 1080 | 11.25 | $38.81 | 5.25 |
| 5 | Dallas → Austin | 195 | 1275 | 6.96 | $24.02 | 3.25 |
| **TOTALS** | | **1275** | **1275** | **45.54** | **$157.10** | **21.25** |

## Success Criteria

1. ✅ **Route Data Complete**: All 5 days with correct distances entered
2. ✅ **Formulas Present**: Cumulative, fuel, cost, and time formulas exist
3. ✅ **Formulas Correct**: Proper cell references (absolute where needed)
4. ✅ **Calculations Accurate**: All values match expected results (within tolerance)
5. ✅ **Totals Row Complete**: Row 7 contains correct sum formulas
6. ✅ **Professional Formatting**: Currency and number formats applied

**Pass Threshold**: 75% (requires correct formulas with accurate calculations)

## Skills Tested

- Multi-column data entry
- Cumulative calculation patterns
- Absolute vs. relative cell references ($J$3)
- Formula copying and pattern recognition
- SUM function for totals
- Number and currency formatting
- Conditional formatting rules
- Real-world budget planning

## Tips

- Use absolute references ($ symbols) for gas price, MPG, and speed cells
- Cumulative distance: Each day adds to the previous cumulative total
- Copy formulas down using Ctrl+C and Ctrl+V or drag fill handle
- Apply currency format: Select cells → Format → Cells → Currency
- For conditional formatting: Format → Conditional Formatting → Condition
- Verify your totals make sense before saving