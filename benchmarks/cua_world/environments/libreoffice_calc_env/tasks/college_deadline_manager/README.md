# College Application Deadline Manager Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, date formulas, sorting, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~12

## Objective

Transform a messy college application deadline spreadsheet into an organized, prioritized action list. This task simulates a real-world scenario where a stressed parent needs to quickly identify which applications need immediate attention. The agent must standardize inconsistent date formats, calculate urgency metrics, sort by priority, and apply visual highlighting to critical deadlines.

## Task Description

**Scenario**: It's October of senior year. A parent started tracking college applications in August but date entry was inconsistent (some "MM/DD/YYYY", some "December 1", some "12-01-23"). Early Action deadlines are approaching and the family needs to quickly see which applications are most urgent.

The agent must:
1. Examine the spreadsheet with inconsistent date formats in the "Deadline" column
2. Standardize all dates to a consistent, machine-readable format
3. Insert a new column "Days Until Deadline" 
4. Create formulas to calculate days remaining until each deadline
5. Sort the entire dataset by urgency (earliest deadlines first)
6. Apply conditional formatting to highlight urgent deadlines (≤14 days)

## Starting Data Structure

| School Name              | Application Type | Deadline     | Essay Required |
|-------------------------|------------------|--------------|----------------|
| State University        | Regular Decision | 02/01/2025   | Yes            |
| Tech Institute          | Early Action     | November 1   | Yes            |
| Liberal Arts College    | Regular Decision | 1-15-2025    | No             |
| Community College       | Rolling          | 12/15/24     | No             |
| Private University      | Early Decision   | 11/15/2024   | Yes            |
| Regional University     | Regular Decision | 2025-01-01   | Yes            |

**Note**: Dates are intentionally inconsistent to simulate real-world messy data entry.

## Expected Results

After completion:
- **All dates standardized**: Deadline column contains proper date values (not text)
- **New urgency column**: "Days Until Deadline" added with formulas
- **Sorted by urgency**: Earliest deadlines appear first
- **Visual highlighting**: Deadlines ≤14 days highlighted with color formatting

## Verification Criteria

1. ✅ **Dates Standardized**: All deadline values are proper date types (not text strings)
2. ✅ **Formulas Correct**: "Days Until Deadline" column contains date arithmetic formulas
3. ✅ **Properly Sorted**: Data sorted by urgency (ascending days until deadline)
4. ✅ **Conditional Formatting Applied**: Urgent deadlines (≤14 days) highlighted with color

**Pass Threshold**: 75% (3/4 criteria must pass)

## Skills Tested

### Data Management
- Recognizing inconsistent data formats
- Date format conversion and standardization
- Data validation and quality assessment

### Formula Creation
- Date arithmetic (deadline - TODAY())
- Using TODAY() function for dynamic calculations
- Formula copying and propagation

### Data Organization
- Multi-column data range selection
- Sorting while maintaining row integrity
- Understanding sort order (ascending/descending)

### Visual Design
- Conditional formatting rule creation
- Threshold-based formatting
- Color coding for visual communication

## Tips for Agents

- **Date Standardization**: Select the Deadline column, use Format → Cells → Date to convert text to dates
- **Insert Column**: Right-click column D header → Insert Column Before/After
- **Formula Syntax**: `=C2-TODAY()` calculates days remaining (assuming deadline is in C2)
- **Sorting**: Select entire data range including headers, then Data → Sort by "Days Until Deadline"
- **Conditional Formatting**: Format → Conditional Formatting → Condition: Cell value ≤ 14
- **Copy Formulas**: Select formula cell, Ctrl+C, select range, Ctrl+V

## Real-World Context

Missing college application deadlines can have serious consequences:
- Lost opportunity at preferred schools
- Forfeited scholarship consideration
- Extra gap year or settling for less desirable options

This task teaches spreadsheet skills that transfer to:
- Business deadline tracking (project milestones, contract renewals)
- Event planning (vendor deadlines, RSVP tracking)
- Compliance management (regulatory filing deadlines)
- Personal finance (bill due dates, tax deadlines)

## Common Pitfalls

❌ **Hardcoding values** instead of using formulas  
❌ **Sorting only one column** (breaks data integrity)  
❌ **Not including headers** when sorting  
❌ **Applying formatting to wrong column**  
❌ **Using text dates** instead of proper date values