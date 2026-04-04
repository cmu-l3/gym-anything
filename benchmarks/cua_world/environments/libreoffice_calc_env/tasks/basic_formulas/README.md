# Basic Formulas Task

**Difficulty**: 🟢 Easy  
**Skills**: Data entry, arithmetic formulas, cell references  
**Duration**: 120 seconds  
**Steps**: ~10

## Objective

Enter numerical data into specified cells and apply basic arithmetic formulas (SUM and AVERAGE) to calculate results. This task tests fundamental spreadsheet operations including cell navigation, data entry, and formula creation.

## Task Description

The agent must:
1. Open a new LibreOffice Calc spreadsheet (provided)
2. Enter the numbers 10, 20, 30, 40, 50 into cells A1 through A5
3. In cell B1, enter a SUM formula that adds all values in A1:A5
4. In cell B2, enter an AVERAGE formula that calculates the average of A1:A5
5. Save the file

## Expected Results

- **A1:A5** contain values 10, 20, 30, 40, 50
- **B1** contains formula `=SUM(A1:A5)` and displays value 150
- **B2** contains formula `=AVERAGE(A1:A5)` and displays value 30

## Verification Criteria

1. ✅ **Data Entry Correct**: Cells A1-A5 contain exact values 10, 20, 30, 40, 50
2. ✅ **SUM Formula**: Cell B1 contains SUM formula and result is 150
3. ✅ **AVERAGE Formula**: Cell B2 contains AVERAGE formula and result is 30
4. ✅ **Formulas Not Hardcoded**: B1 and B2 contain formulas (not just values)

**Pass Threshold**: 75% (3/4 criteria must pass)

## Skills Tested

- Cell navigation (arrow keys, mouse clicks)
- Numerical data entry
- Formula syntax (starting with `=`)
- Built-in function usage (SUM, AVERAGE)
- Cell range references (A1:A5)
- Save file operation

## Setup

The setup script:
- Launches LibreOffice Calc with a new spreadsheet
- Focuses the Calc window
- Positions cursor at cell A1

## Export

The export script:
- Saves the file as `/home/ga/Documents/basic_formulas.ods`
- Closes LibreOffice Calc

## Verification

Verifier parses the ODS file and checks:
1. Cell values in A1-A5
2. Formula text in B1 and B2
3. Calculated results in B1 and B2
4. Presence of formulas (not just values)
