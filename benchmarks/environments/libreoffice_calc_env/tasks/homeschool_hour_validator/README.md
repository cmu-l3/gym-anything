# Homeschool Hour Compliance Validator Task

**Difficulty**: 🟡 Medium
**Estimated Steps**: 20
**Timeout**: 240 seconds (4 minutes)

## Objective

Analyze a homeschool lesson log and verify compliance with state-mandated minimum instruction hours per subject. Create a summary report with formulas that calculate total hours by subject, compare against requirements, identify deficiencies, and apply visual formatting to highlight problem areas.

## Scenario

Sarah is a homeschooling parent facing an upcoming portfolio review in two weeks. She's been informally tracking lessons all year but now needs official numbers. The state requires minimum instruction hours per subject, and she must prove compliance or identify gaps requiring makeup lessons.

## Starting State

- LibreOffice Calc opens with a partially-complete lesson log spreadsheet
- **Lesson Log** (columns A-D):
  - Date, Subject, Duration (hours), Description
  - Contains ~80 lesson entries from the school year
  - Some variation in data (realistic messiness)
- **State Requirements** table (columns F-G):
  - Subject, Minimum Hours
  - 6 subjects with required minimums

## Required Actions

### 1. Create Summary Analysis Section
- Set up a clear summary area (e.g., starting at row 85 or on separate area)
- Column headers: Subject, Hours Completed, Hours Required, Difference, Status

### 2. Calculate Hours by Subject
- Use **SUMIF** formulas to total hours for each subject from the lesson log
- Calculate for all 6 subjects: Mathematics, Language Arts, Science, Social Studies, Physical Education, Arts

### 3. Reference Requirements
- Link to the state requirements (Minimum Hours column)
- Can use cell references or VLOOKUP

### 4. Calculate Deficiency/Surplus
- Formula: Hours Completed - Hours Required
- Shows how many hours over/under each subject is

### 5. Determine Status
- Use **IF** formula to create status indicator
- "COMPLIANT" if hours met or exceeded
- "DEFICIENT" if below minimum

### 6. Apply Conditional Formatting
- Format Status or Difference column with color coding
- Red background for DEFICIENT/negative values
- Green background for COMPLIANT/positive values
- Use Format → Conditional → Condition

### 7. Save the Analysis
- File saves automatically as ODS format

## Success Criteria

1. ✅ **Formulas Present**: SUMIF (or equivalent) formulas detected in summary section
2. ✅ **Calculations Accurate**: Hours totals match expected values (≥4/6 subjects correct within ±0.5 hour)
3. ✅ **Deficiency Identified**: Correctly identifies which subjects are below minimum hours
4. ✅ **Visual Formatting Applied**: Conditional formatting detected on status/difference columns
5. ✅ **Complete Coverage**: All 6 subjects analyzed

**Pass Threshold**: 80% (4 out of 5 criteria)

## Skills Tested

- **SUMIF function**: Aggregate data by category
- **IF function**: Conditional logic for status determination
- **Cell references**: Absolute and relative references
- **Conditional formatting**: Visual indicators based on values
- **Data analysis**: Interpret requirements and identify gaps
- **Formula-based workflow**: Use formulas instead of manual calculation

## State Requirements

| Subject           | Minimum Hours |
|-------------------|---------------|
| Mathematics       | 120           |
| Language Arts     | 160           |
| Science           | 100           |
| Social Studies    | 100           |
| Physical Education| 60            |
| Arts              | 40            |

**Total Required**: 580 hours minimum

## Example Summary Output

| Subject           | Hours Completed | Hours Required | Difference | Status     |
|-------------------|-----------------|----------------|------------|------------|
| Mathematics       | 125.5           | 120            | +5.5       | COMPLIANT  |
| Language Arts     | 168.0           | 160            | +8.0       | COMPLIANT  |
| Science           | 95.5            | 100            | -4.5       | DEFICIENT  |
| Social Studies    | 103.0           | 100            | +3.0       | COMPLIANT  |
| Physical Education| 57.0            | 60             | -3.0       | DEFICIENT  |
| Arts              | 38.5            | 40             | -1.5       | DEFICIENT  |

*Note: This example shows the desired output structure with proper formulas and formatting.*

## Tips

- **SUMIF syntax**: `=SUMIF(range_to_check, criteria, sum_range)`
  - Example: `=SUMIF($B$2:$B$82, "Mathematics", $C$2:$C$82)`
- **IF syntax**: `=IF(test, value_if_true, value_if_false)`
  - Example: `=IF(D85>=0, "COMPLIANT", "DEFICIENT")`
- Use **absolute references** ($A$1) for data ranges that shouldn't change when copying formulas
- Access conditional formatting: Format → Conditional → Condition
- You can create rules based on cell values or formulas

## Real-World Context

Homeschooling families must document instruction hours for annual reviews. Failure to meet minimums can result in:
- Mandatory remediation plans
- Additional evaluations
- Loss of homeschool approval

This task simulates the stress of deadline-driven compliance with imperfect tracking data—a genuine pain point for homeschooling parents.