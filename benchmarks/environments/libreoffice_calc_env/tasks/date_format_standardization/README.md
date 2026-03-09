# LibreOffice Calc Date Format Standardization Task (`date_format_standardization@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Date handling, format conversion, data cleaning, pattern recognition  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Standardize inconsistent date formats within a sales data spreadsheet. A small business owner has exported sales data from their point-of-sale system, but due to a software update midway through the tracking period, dates are recorded in three different formats. Convert all dates to consistent ISO format (YYYY-MM-DD) to enable proper chronological sorting and analysis.

## Scenario

You're helping a local shop owner prepare their Q1 sales report for tomorrow's meeting with their accountant. They just discovered that their POS system update in mid-January changed how dates are recorded. Now half the dates look wrong when sorted, and the accountant needs everything in standard YYYY-MM-DD format for their accounting software.

## Task Description

The spreadsheet contains sales transactions with dates in three formats:
- **MM/DD/YYYY** (e.g., "03/15/2024") - early January transactions
- **DD-MM-YYYY** (e.g., "15-03-2024") - mid to late January after first update
- **YYYY-MM-DD** (e.g., "2024-03-15") - February onward (already correct)

The agent must:
1. Open the provided sales data CSV in LibreOffice Calc
2. Identify the different date format patterns in Column A
3. Convert all dates to YYYY-MM-DD format
4. Verify conversion accuracy (no date/month swaps)
5. Ensure dates sort chronologically
6. Save the standardized file

## Starting Data Structure

| Date (Mixed Formats) | Product | Amount | Customer |
|---------------------|---------|--------|----------|
| 01/05/2024 | Widget A | $45.99 | John Smith |
| 01/06/2024 | Widget B | $32.50 | Jane Doe |
| 08-01-2024 | Widget C | $78.25 | Bob Johnson |
| 2024-02-01 | Widget A | $45.99 | Alice Brown |
| ... | ... | ... | ... |

## Expected Results

All dates in Column A should be in **YYYY-MM-DD** format:

| Date (Standardized) | Product | Amount | Customer |
|--------------------|---------|--------|----------|
| 2024-01-05 | Widget A | $45.99 | John Smith |
| 2024-01-06 | Widget B | $32.50 | Jane Doe |
| 2024-01-08 | Widget C | $78.25 | Bob Johnson |
| 2024-02-01 | Widget A | $45.99 | Alice Brown |
| ... | ... | ... | ... |

## Verification Criteria

1. ✅ **All ISO Format**: 100% of dates match YYYY-MM-DD pattern
2. ✅ **All Valid Dates**: Every date is parsable and represents a real calendar date
3. ✅ **Chronological Logic**: Dates follow reasonable chronological progression
4. ✅ **No Data Loss**: Row count and data completeness maintained
5. ✅ **Correct Interpretation**: Sample spot checks confirm dates weren't misinterpreted

**Pass Threshold**: 75% (requires substantial standardization with minimal errors)

## Skills Tested

- Visual pattern recognition across mixed formats
- Date format conversion (TEXT, DATE, DATEVALUE functions)
- Understanding date internal representation in Calc
- Formula application to selected ranges
- Helper column workflow
- Data validation and verification
- Systematic problem-solving approach

## Recommended Approach

### Option 1: Helper Column with Formulas
1. Insert Column B for "Standardized Date"
2. Use IF statements to detect and convert each format type
3. Copy formulas down
4. Copy helper column as values back to Column A
5. Delete helper column

### Option 2: Format Cells Dialog
1. Select cells with same format
2. Use Format → Cells → Date
3. Apply YYYY-MM-DD format code
4. Repeat for each format group

### Option 3: TEXT and DATE Functions