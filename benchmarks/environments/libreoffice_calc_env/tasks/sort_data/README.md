# Sort Data Task

**Difficulty**: 🟢 Easy
**Estimated Steps**: 20
**Timeout**: 180 seconds

## Objective

Sort a dataset by a specific column in ascending order (lowest to highest). This task tests data manipulation and sorting operations in spreadsheets.

## Starting State

- LibreOffice Calc opens with student score data
- Data contains: Name and Score columns
- 5 students with various scores

## Data Layout

| Name    | Score |
|---------|-------|
| Alice   | 85    |
| Bob     | 72    |
| Charlie | 95    |
| David   | 63    |
| Eve     | 88    |

## Required Actions

1. Select the data range (including headers)
2. Navigate to Data → Sort menu
3. Choose to sort by the "Score" column
4. Select ascending order (lowest to highest)
5. Execute the sort
6. Save the file

## Expected Result After Sorting

| Name    | Score |
|---------|-------|
| David   | 63    |
| Bob     | 72    |
| Alice   | 85    |
| Eve     | 88    |
| Charlie | 95    |

## Success Criteria

1. ✅ Score column sorted in ascending order
2. ✅ Name-Score pairs correctly maintained (David→63, Bob→72, etc.)
3. ✅ All data preserved (no data loss during sorting)

**Pass Threshold**: 66% (2 out of 3 criteria)

## Skills Tested

- Data range selection
- Menu navigation (Data → Sort)
- Sort dialog configuration
- Maintaining data integrity during operations
- Understanding ascending vs descending order

## Tips

- Always select the entire data range including all columns
- Make sure to include the header row
- Verify that "My data has headers" is checked in the sort dialog
- The Name column should move with the Score column (row integrity)
