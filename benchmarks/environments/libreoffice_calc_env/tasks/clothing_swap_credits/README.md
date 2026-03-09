# Clothing Swap Credit Manager Task

**Difficulty**: 🟡 Medium  
**Skills**: Data entry, formulas, conditional formatting, sorting, aggregation  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Manage a community clothing swap event by tracking participant check-ins, item contributions, and withdrawal credits. Apply formulas to calculate remaining credits, use conditional formatting to flag violations, sort data by credits, and create summary statistics.

## Starting State

- LibreOffice Calc opens with a pre-populated spreadsheet
- 18 participants with registration data
- Some participants already checked in (Column C filled)
- Some participants have taken items (Column D has values)
- Sarah Martinez, James Chen, and Priya Patel have NOT checked in yet (Column C empty)

## Data Layout

| Participant Name | Registered Items | Actual Items Brought | Items Taken | Remaining Credits |
|------------------|------------------|---------------------|-------------|------------------|
| Sarah Martinez   | 5                | (empty)             | 0           | (formula needed) |
| James Chen       | 4                | (empty)             | 0           | (formula needed) |
| ...              | ...              | ...                 | ...         | ...              |

## Required Actions

### 1. Update Check-in Data
Enter values in Column C (Actual Items Brought) for participants who just arrived:
- Sarah Martinez: 6 items
- James Chen: 3 items
- Priya Patel: 8 items

### 2. Create Credits Calculation Formula
In Column E (Remaining Credits), create formula: `=IF(ISBLANK(C2),"Not Checked In",C2-D2)`
- Copy formula down to all participant rows
- Formula should calculate: Actual Brought - Items Taken
- Handle unchecked-in participants with IF/ISBLANK

### 3. Apply Conditional Formatting
- Select Column E (Remaining Credits)
- Apply conditional formatting: values < 0 should be highlighted (red background)
- This flags participants who took more than they brought

### 4. Sort Data by Credits
- Select entire data range (A1:E19 including headers)
- Sort by Column E (Remaining Credits) in ascending order
- Brings negative credits to the top

### 5. Create Summary Statistics
Below the data table (around row 23), create:
- Total Items in Circulation: `=SUM(C2:C19)` 
- Total Items Taken: `=SUM(D2:D19)`
- Items Still Available: `=B23-B24` (difference)
- Participants Over Limit: `=COUNTIF(E2:E19,"<0")` (count negatives)

## Success Criteria

1. ✅ **Check-in Data Entered**: Sarah (6), James (3), Priya (8) in Column C
2. ✅ **Credits Formula Correct**: Column E has subtraction formula with error handling
3. ✅ **Conditional Formatting Applied**: Negative credits visually highlighted
4. ✅ **Data Sorted Properly**: Sorted by Credits column ascending
5. ✅ **Summary Statistics Present**: 4 summary metrics with formulas
6. ✅ **Calculations Accurate**: Spot-checked values match expectations

**Pass Threshold**: 70% (4 out of 6 criteria)

## Skills Tested

- Data entry in specific cells
- IF and ISBLANK functions
- Arithmetic formulas with cell references
- Conditional formatting rules
- Data sorting operations
- SUM and COUNTIF aggregation functions
- Range references
- Business logic implementation

## Real-World Context

This simulates managing a community clothing swap event where:
- Participants bring items to exchange
- They can only take as many items as they brought
- Organizers need to enforce fairness
- Real-time tracking during busy event
- Quick identification of rule violations

## Tips

- Use Ctrl+D to copy formula down a column
- Format → Conditional → Condition for formatting rules
- Data → Sort for sorting operations
- COUNTIF counts cells meeting a condition
- IF(ISBLANK()) prevents errors for empty cells