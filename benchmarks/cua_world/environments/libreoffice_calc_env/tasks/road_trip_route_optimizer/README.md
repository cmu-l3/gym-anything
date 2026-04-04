# Road Trip Route Optimizer Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, cumulative calculations, multi-variable analysis  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Complete a partially-filled road trip planning spreadsheet by adding formulas to calculate fuel costs, driving times, and cumulative mileage. This task tests understanding of formula chaining, cell references, and decision-support calculations.

## Human Context

Maya's family is planning a summer road trip from Seattle to visit national parks, but they're on a tight budget ($400 for gas) and limited vacation time (must complete in under 24 hours of driving). Maya started entering the route data but got interrupted. She needs formulas to determine:

1. **Total fuel cost** - Will they exceed their $400 gas budget?
2. **Total driving time** - Can they complete this realistically?
3. **Cost per leg** - Which segments are most expensive?
4. **Cumulative mileage** - How far from home at each stop?

## Task Description

The agent receives a spreadsheet with:
- **Route legs** pre-filled (8 destinations)
- **Distance (miles)** for each leg
- **Constants**: Vehicle MPG (25), Gas Price ($3.80/gal), Avg Speed (60 mph), Budget ($400)

The agent must:
1. Calculate **Fuel Cost** for each leg: `(Miles ÷ MPG) × Gas Price`
2. Calculate **Drive Time** for each leg: `Miles ÷ Speed`
3. Calculate **Cumulative Miles**: Running total of distance traveled
4. Calculate **Total Fuel Cost**: SUM of all fuel costs
5. Calculate **Total Drive Time**: SUM of all drive times
6. Apply appropriate formatting (currency for costs, decimals for time)

## Expected Results

### Route Data (Pre-filled)
| Leg | Destination          | Miles |
|-----|----------------------|-------|
| 1   | Seattle to Portland  | 173   |
| 2   | Portland to Crater L.| 285   |
| 3   | Crater Lake to Bend  | 90    |
| 4   | Bend to Burns        | 130   |
| 5   | Burns to Boise       | 185   |
| 6   | Boise to Sun Valley  | 155   |
| 7   | Sun Valley to Spokane| 410   |
| 8   | Spokane to Seattle   | 280   |

### Formulas to Add
- **Fuel Cost (Column D)**: `=(C2/25)*3.80` or `=(C2/$B$15)*$B$16` (with absolute refs)
- **Drive Time (Column E)**: `=C2/60` or `=C2/$B$17`
- **Cumulative Miles (Column F)**: First row `=C2`, subsequent `=F2+C3`, etc.
- **Totals**: `=SUM(D2:D9)` and `=SUM(E2:E9)`

### Expected Calculations
- **Total Distance**: 1,708 miles
- **Total Fuel Cost**: ~$260 (under budget!)
- **Total Drive Time**: ~28.5 hours (exceeds 24-hour goal)

## Verification Criteria

1. ✅ **Formulas Present**: Fuel cost, drive time, cumulative miles contain formulas (not hardcoded values)
2. ✅ **Fuel Cost Accurate**: All leg fuel costs calculated correctly (±$0.10 tolerance)
3. ✅ **Drive Time Accurate**: All leg drive times calculated correctly (±0.05 hrs tolerance)
4. ✅ **Cumulative Miles Correct**: Running totals increase logically
5. ✅ **Totals Accurate**: Total fuel cost and drive time use SUM formulas correctly
6. ✅ **Proper Formatting**: Currency ($) for costs, decimal precision for times
7. ✅ **No Formula Errors**: No #REF!, #VALUE!, #DIV/0! errors

**Pass Threshold**: 85% (requires correct formulas with minimal errors)

## Skills Tested

- **Formula Creation**: Basic arithmetic operations in cells
- **Cell References**: Relative vs. absolute references
- **Formula Copying**: Replicating formulas down columns
- **SUM Function**: Totaling columns
- **Cumulative Totals**: Building running sums
- **Cross-Column References**: Formulas using multiple columns
- **Number Formatting**: Currency and decimal formatting
- **Logical Verification**: Checking if results make real-world sense

## Tips

- Use absolute references ($B$15) for constants so formulas copy correctly
- Cumulative miles: First leg = distance, each subsequent = previous cumulative + current distance
- Verify totals make sense: ~1,700 miles, ~$260 fuel, ~28 hours
- Format costs as currency for readability
- Check that formulas copied correctly (no #REF! errors)