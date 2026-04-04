# LibreOffice Calc Tide Window Calculator Task (`tide_window_calculator@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Time arithmetic, logical functions, multi-condition filtering  
**Duration**: 180 seconds  
**Steps**: ~12-15

## Objective

Analyze a week's worth of tide data to identify optimal windows for tidepooling or clamming activities. This task tests time-based calculations, conditional logic, and understanding of cyclical natural phenomena. The agent must filter tide data by multiple criteria (tide type, height, timing, and duration) to recommend the best days for coastal activities.

## Task Description

The agent must:
1. Open a spreadsheet containing tide predictions for a coastal location (7 days of data)
2. Identify LOW tides (filtering out high tides)
3. Determine which low tides occur during usable daylight hours (7:00 AM - 7:00 PM)
4. Filter for optimal tide heights (≤ 1.5 feet for best tidepooling)
5. Calculate the duration of safe activity windows (time until tide returns)
6. Identify days with at least one optimal low tide meeting all criteria
7. Create summary statistics showing optimal tide counts and recommended days
8. Save the completed analysis

## Expected Results

### Required Columns/Calculations:
- **Is_Low_Tide**: Boolean/text indicating if tide type is "Low"
- **In_Daylight**: Boolean/text indicating if tide time is between 7:00 AM and 7:00 PM
- **Optimal_Height**: Boolean/text indicating if height ≤ 1.5 feet
- **Activity_Window_Hours**: Calculated duration between low tide and next high tide
- **Meets_All_Criteria**: Boolean/text indicating ALL conditions met
- **Summary Section**: 
  - Total low tides count
  - Low tides in daylight count
  - Optimal tides count (meeting all criteria)
  - Recommended days list

### Verification Criteria

1. ✅ **Low Tides Identified**: All low tide entries correctly marked (14 expected for a week)
2. ✅ **Daylight Window Filter**: Time comparison logic correctly identifies 7 AM - 7 PM window
3. ✅ **Height Threshold Applied**: Tides ≤ 1.5 feet correctly identified
4. ✅ **Activity Windows Calculated**: Duration formulas present and logical
5. ✅ **Summary Statistics Accurate**: Counts match actual data (±1 tolerance)
6. ✅ **Recommended Days Valid**: At least 2 days marked as suitable for activities

**Pass Threshold**: 60% (4 out of 6 criteria must pass)

## Skills Tested

- Time/date function usage (HOUR, MINUTE, TIME)
- Logical functions (IF, AND, OR)
- Conditional filtering with multiple criteria
- Time arithmetic and duration calculations
- Cell range references and formula copying
- Summary statistics (COUNT, COUNTIF, SUMPRODUCT)
- Understanding of time-based natural cycles

## Sample Tide Data Format

| Date       | Time  | Height_ft | Type |
|------------|-------|-----------|------|
| 2024-03-18 | 05:23 | 0.8       | Low  |
| 2024-03-18 | 11:45 | 9.2       | High |
| 2024-03-18 | 17:34 | 1.2       | Low  |
| 2024-03-18 | 23:58 | 8.9       | High |

## Tips for Agents

- Use `HOUR(time_cell)` to extract hour from time values
- Use `AND()` function to combine multiple conditions
- For time windows: `=AND(HOUR(B2)>=7, HOUR(B2)<19)`
- For height check: `=D2="Low"` combined with `=C2<=1.5`
- Activity window: Calculate time difference to next high tide
- Use `COUNTIF` or `COUNTIFS` for summary statistics
- Remember: Lower tide heights are better for tidepooling (more area exposed)

## Real-World Context

This task simulates planning for:
- Recreational clamming and shellfish harvesting
- Tidepooling expeditions with children
- Coastal photography during golden hour low tides
- Marine biology surveys of intertidal zones
- Beach exploration of sea caves and rock formations

Success requires understanding that not all low tides are useful—timing, height, and available activity time all matter for safe and productive coastal activities.