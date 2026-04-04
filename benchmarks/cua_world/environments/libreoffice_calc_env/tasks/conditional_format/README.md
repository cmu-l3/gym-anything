# Conditional Formatting Task

**Difficulty**: 🟡 Medium
**Estimated Steps**: 40
**Timeout**: 300 seconds (5 minutes)

## Objective

Apply conditional formatting to highlight cells based on their values. This task tests advanced formatting features and rule-based cell styling.

## Starting State

- LibreOffice Calc opens with student score data
- Data contains: Student names and their scores
- 6 students with scores ranging from 45 to 95

## Data Layout

| Student  | Score |
|----------|-------|
| Alice    | 85    |
| Bob      | 58    |
| Charlie  | 92    |
| David    | 45    |
| Eve      | 78    |
| Frank    | 95    |

## Required Actions

1. Select the Score column (B2:B7 or similar)
2. Navigate to Format → Conditional Formatting menu
3. Create formatting rule for high scores (≥ 80)
   - Apply green background or text color
4. Create formatting rule for low scores (< 60)
   - Apply red background or text color
5. Apply the rules
6. Save the file in ODS format

## Expected Result

- **Green highlighting**: Alice (85), Charlie (92), Frank (95)
- **Red highlighting**: Bob (58), David (45)
- **No highlighting**: Eve (78) - between thresholds

## Success Criteria

1. ✅ Student data preserved (6+ rows)
2. ✅ File saved in ODS format (required for formatting)
3. ✅ Conditional formatting detected (background colors applied)
4. ✅ At least 2 cells have formatting applied

**Pass Threshold**: 75% (3 out of 4 criteria)

## Skills Tested

- Range selection
- Conditional formatting dialog navigation
- Creating formatting rules
- Understanding logical conditions (≥, <)
- Color and style application
- ODS format requirements

## Tips

- Select the entire Score column before applying formatting
- Format → Conditional Formatting → Condition...
- First rule: "Cell value is" "greater than or equal to" "80"
- Second rule: "Cell value is" "less than" "60"
- Choose distinct colors for easy verification
- Must save as ODS to preserve formatting (XLSX also works)
