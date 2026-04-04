# Maintenance Request Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Date formulas, conditional formatting, summary statistics, status tracking  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Transform a basic maintenance request log into a functional tracking system with time-based calculations, conditional formatting for priority highlighting, and summary statistics for management reporting. This task simulates a real-world property management scenario where urgent repairs need to be identified quickly.

## Scenario

You're a property manager for a 12-unit apartment building. Maintenance requests have been logged in a basic spreadsheet, but it lacks any way to see which requests are overdue or calculate costs. Your boss needs a proper tracking system today because a tenant is threatening to withhold rent over an "ignored" repair.

## Task Description

The agent receives a pre-populated spreadsheet with maintenance requests containing:
- **Request Date**: When the issue was reported
- **Unit #**: Apartment number (101-112)
- **Issue Description**: What needs fixing
- **Status**: Open, In Progress, or Completed
- **Assigned To**: Maintenance person (or empty if unassigned)
- **Cost**: Repair cost (or $0 if not yet completed)
- **Days Open**: EMPTY - needs formulas added

The agent must:

1. **Add time calculation formulas** to the "Days Open" column using TODAY() function
2. **Apply conditional formatting** to highlight overdue items (>7 days) in red/orange
3. **Add status-based formatting** to the Status column (color-coded by status)
4. **Create summary statistics** section with formulas for:
   - Total number of requests
   - Count of Open/In Progress items
   - Count of overdue requests (>7 days, excluding Completed)
   - Total maintenance costs
5. **Format the summary section** for professional appearance

## Expected Results

### Days Open Column (Column G)
- All cells contain formulas like `=TODAY()-A2` (where A2 is Request Date)
- Calculated values show realistic day counts (0-30 days)

### Conditional Formatting
- **Days Open > 7**: Red or orange background for urgency
- **Status column**: Color-coded (e.g., Open=Yellow, In Progress=Blue, Completed=Green)

### Summary Section (Below data table)
- Total Requests: `=COUNTA(A2:A21)` or similar
- Open/In Progress: `=COUNTIF(D2:D21,"Open")+COUNTIF(D2:D21,"In Progress")`
- Overdue Count: `=COUNTIFS(D2:D21,"<>Completed",G2:G21,">7")`
- Total Costs: `=SUM(F2:F21)` with currency formatting

## Verification Criteria

1. ✅ **Days Formula Present**: Days Open column contains TODAY()-based formulas (90%+ of rows)
2. ✅ **Conditional Formatting Applied**: Visual highlighting present for overdue items
3. ✅ **Status Color-Coding**: Status column has conditional formatting
4. ✅ **Summary Statistics**: Summary section with COUNT/SUM/COUNTIF formulas exists
5. ✅ **Overdue Logic Correct**: Overdue count excludes completed items
6. ✅ **Data Integrity**: Original request data preserved

**Pass Threshold**: 70% (requires at least 4 out of 6 criteria)

## Skills Tested

- **Date arithmetic**: TODAY() function and date subtraction
- **Conditional formatting**: Creating rules based on cell values
- **Summary functions**: COUNT, COUNTIF, COUNTIFS, SUM
- **Visual design**: Using colors to communicate urgency
- **Formula copying**: Applying formulas consistently across ranges
- **Business logic**: Understanding "overdue" means open/in-progress AND >7 days

## Data Structure

| Request Date | Unit | Issue Description | Status | Assigned To | Cost | Days Open |
|--------------|------|-------------------|--------|-------------|------|-----------|
| 2024-01-05 | 101 | Kitchen sink dripping | Completed | Mike P. | $120 | (empty) |
| 2024-01-12 | 105 | Toilet won't flush | In Progress | Sarah L. | $200 | (empty) |
| 2024-01-15 | 103 | No hot water | Open | | $0 | (empty) |
| ... | ... | ... | ... | ... | ... | (empty) |

## Tips

- Use `Ctrl+Home` to go to cell A1
- Formula syntax: `=TODAY()-A2` calculates days elapsed
- Copy formula down: Select cell, Ctrl+C, select range, Ctrl+V
- Conditional formatting: Format → Conditional → Condition (or Conditional Formatting)
- COUNTIF syntax: `=COUNTIF(range, "criteria")`
- COUNTIFS for multiple criteria: `=COUNTIFS(range1, criteria1, range2, criteria2)`

## Real-World Application

This pattern applies to:
- IT helpdesk ticket tracking
- Customer service case management  
- Project task status dashboards
- Equipment maintenance logs
- Bug/issue tracking systems
- Sales pipeline management