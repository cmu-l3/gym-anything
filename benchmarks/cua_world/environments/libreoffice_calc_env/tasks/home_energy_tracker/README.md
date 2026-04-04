# Home Energy Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Formulas, cell references, arithmetic operations, percentage calculations  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Complete a home energy usage tracking spreadsheet by adding formulas to calculate monthly electricity consumption, costs, and year-over-year comparisons. This task simulates a real-world scenario where homeowners track utility usage to identify patterns and reduce costs.

## Scenario

A homeowner has been recording monthly electric meter readings for a year but hasn't analyzed the data. They want to calculate actual usage, costs, and compare to last year to see if their energy-saving efforts are working.

## Task Description

The agent must:
1. Open the pre-created energy tracking spreadsheet with meter readings
2. Add formulas in Column C to calculate monthly kWh used (current - previous reading)
3. Add formulas in Column D to calculate monthly cost (kWh × rate + base fee)
4. Add formulas in Column F to calculate year-over-year percentage change
5. Add summary formulas for annual totals, averages, and maximum usage
6. Save the completed spreadsheet

## Spreadsheet Structure

| Column | Content | Formula Required |
|--------|---------|------------------|
| A | Month (Jan 2024, Feb 2024...) | No (pre-filled) |
| B | Meter Reading (cumulative kWh) | No (pre-filled) |
| C | kWh Used | Yes: =B3-B2 (difference) |
| D | Cost ($) | Yes: =C2*$G$2+$G$3 |
| E | Previous Year kWh | No (reference data) |
| F | Change % | Yes: =(C2-E2)/E2*100 |
| G2 | Rate ($/kWh): 0.14 | No (pre-filled) |
| G3 | Base Fee ($): 12 | No (pre-filled) |

## Expected Formulas

**Monthly kWh Usage (Column C):**
- C3: `=B3-B2` (Feb reading minus Jan reading)
- C4: `=B4-B3` (Mar reading minus Feb reading)
- Continue pattern through C13

**Monthly Cost (Column D):**
- D2: `=(C2*$G$2)+$G$3` or `=C2*0.14+12`
- Copy down through D13
- Note: Using $G$2 and $G$3 (absolute references) allows easy copying

**Year-over-Year Change % (Column F):**
- F2: `=(C2-E2)/E2*100`
- Copy down through F13
- Negative values indicate reduction (good!)

**Summary Statistics:**
- Total annual kWh: `=SUM(C2:C13)`
- Total annual cost: `=SUM(D2:D13)`
- Average monthly kWh: `=AVERAGE(C2:C13)`
- Highest usage month: `=MAX(C2:C13)`
- Average YoY change: `=AVERAGE(F2:F13)`

## Verification Criteria

1. ✅ **kWh Formulas Present**: Column C contains subtraction formulas (≥10 cells)
2. ✅ **Cost Formulas Correct**: Column D formulas include rate multiplication and base fee
3. ✅ **Percentage Formulas Valid**: Column F contains percentage change formulas
4. ✅ **Values Reasonable**: kWh values 50-2000, costs $20-$300
5. ✅ **Summary Formulas Present**: Uses SUM, AVERAGE, MAX functions
6. ✅ **Calculations Accurate**: Spot-check calculations within 1% tolerance

**Pass Threshold**: 70% (requires most formulas with acceptable accuracy)

## Skills Tested

- Cell reference understanding (B3-B2, C2*G2, etc.)
- Relative vs. absolute references ($G$2)
- Formula copying and auto-fill
- Arithmetic operators (-, *, +, /)
- Built-in functions (SUM, AVERAGE, MAX)
- Percentage calculations
- Multi-step formula construction
- Understanding real-world utility billing

## Sample Data Values

The spreadsheet includes realistic electric meter readings:
- Starting reading: ~15,280 kWh (January)
- Ending reading: ~21,400 kWh (December)
- Monthly usage varies: 380-790 kWh (higher in summer/winter)
- Previous year data provided for comparison

## Tips

- Start with Column C (kWh calculation) as it's needed for Columns D and F
- Use arrow keys to navigate between cells efficiently
- After entering first formula, use Ctrl+C and Ctrl+V to copy, or drag fill handle
- Verify one calculation manually before copying formulas
- Summary formulas go in cells below the main data table
- Press Enter to confirm formulas, Esc to cancel

## Real-World Context

This pattern applies to tracking:
- Water usage and bills
- Natural gas consumption
- Internet bandwidth
- Any metered service with cumulative readings and cost calculations