# Course Schedule Conflict Checker Task

**Difficulty**: 🟡 Medium  
**Skills**: Complex formulas, conditional formatting, time logic, problem-solving  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Analyze a college course schedule to identify time conflicts between selected courses. Create formulas to detect overlapping meeting times, apply conditional formatting to highlight conflicts, and calculate total credit hours to verify degree requirements. This addresses a real-world problem students face during course registration.

## Task Description

The agent must:
1. Examine a course schedule spreadsheet with 6 selected courses
2. Create a "Time Conflicts" column to detect scheduling conflicts
3. Build formulas that check if courses meet on common days AND have overlapping times
4. Apply conditional formatting to highlight conflicting courses
5. Calculate total credit hours using SUM formula
6. Display enrollment status (FULL-TIME/PART-TIME/OVERLOAD) based on credit total

## Starting State

- LibreOffice Calc opens with `fall_2025_courses.csv`
- Columns: Course Code, Course Name, Days, Start Time, End Time, Credits, Selected
- 6 courses marked as "Selected" (Yes)
- Some courses have deliberate time conflicts

## Sample Data

| Course Code | Course Name | Days | Start Time | End Time | Credits | Selected |
|-------------|-------------|------|------------|----------|---------|----------|
| CS101 | Intro to Programming | MWF | 9:00 AM | 9:50 AM | 3 | Yes |
| MATH201 | Calculus II | MWF | 9:30 AM | 10:20 AM | 4 | Yes |
| PHYS101 | Physics I + Lab | TTh | 10:00 AM | 11:50 AM | 4 | Yes |

**Known Conflicts:**
- CS101 vs MATH201: Both meet MWF with 20-minute overlap (9:30-9:50 AM)
- PHYS101 vs HIST150: Both meet TTh with overlap

## Required Actions

1. **Add Conflict Detection Column**
   - Create new column header "Time Conflicts" or similar
   - Position after Credits column

2. **Build Conflict Detection Formulas**
   - Compare each course against all other selected courses
   - Check for common days (e.g., both have "M" in days)
   - Check for time overlap
   - Display conflicting course code(s) or "Clear"/"None"

3. **Apply Conditional Formatting**
   - Highlight rows with conflicts (red/orange)
   - Optionally highlight clear schedules (green)

4. **Calculate Total Credits**
   - Add "Total Credits:" label
   - Use SUM formula for all selected courses
   - Display result

5. **Add Enrollment Status**
   - Create status indicator:
     - "FULL-TIME" if ≥12 credits
     - "PART-TIME" if <12 credits
     - "OVERLOAD" if >18 credits
   - Use IF formula with threshold logic

## Success Criteria

1. ✅ **Conflict Column Created**: New column added for conflict detection
2. ✅ **Detection Formulas Present**: Formulas (starting with =) analyze conflicts
3. ✅ **Known Conflicts Identified**: At least 2 out of 3 known conflicts detected
4. ✅ **Conditional Formatting Applied**: Visual highlighting on conflict rows
5. ✅ **Credit Calculation Present**: SUM formula totals credit hours
6. ✅ **Accurate Credit Total**: Calculated total matches expected (within 0.5)
7. ✅ **Status Indicator Correct**: Full-time/part-time/overload matches total
8. ✅ **No False Positives**: Non-conflicting courses not incorrectly flagged

**Pass Threshold**: 70% (requires at least 6/8 criteria)

## Skills Tested

- Complex IF/AND/OR logical formulas
- Time comparison logic
- String matching (day abbreviations)
- Conditional formatting with formula-based rules
- SUM functions and range references
- Nested IF statements for status logic
- Problem-solving and practical workflow automation

## Tips

- Time overlap occurs when: start1 < end2 AND start2 < end1
- Day overlap: check if any letter appears in both day strings
- Use helper columns if needed for intermediate calculations
- Conditional formatting: Format → Conditional Formatting → Condition
- Test your formula on one row before copying to all rows

## Real-World Value

This skill transfers to:
- Employee shift scheduling
- Meeting room conflict detection
- Resource allocation problems
- Calendar optimization
- Constraint satisfaction scenarios