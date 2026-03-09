# Theater Rehearsal Conflict Detector Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-sheet formulas, cross-referencing, conditional logic, VLOOKUP/COUNTIFS  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Identify scheduling conflicts in a community theater rehearsal schedule by cross-referencing actor availability. This task tests multi-sheet data integration, conditional logic formulas, and practical problem-solving skills.

## Context

You're the assistant director for "Much Ado About Nothing" at Riverside Community Theater. Three actors just sent updated availability due to work conflicts and family emergencies. The director needs to know ASAP which scheduled rehearsals are now impossible so reschedule emails can be sent before people drive to the theater.

## Task Description

The agent receives a spreadsheet with three sheets:
1. **Rehearsal_Schedule**: Scheduled rehearsals with dates, times, scenes, and assigned actors
2. **Actor_Availability**: Updated actor availability showing when each actor is UNAVAILABLE
3. **Scene_Requirements**: Which actors are required for each scene (optional reference)

**Your Mission**: Add a "CONFLICT" detection column that identifies rehearsals where at least one required actor is unavailable. Use formulas to cross-reference the data, not manual checking.

## Starting State

- LibreOffice Calc opens with `theater_schedule.ods` containing 3 sheets
- Rehearsal_Schedule has ~10 rehearsals over 7 days
- Actor_Availability shows 4-6 unavailability periods
- 4-6 rehearsals have conflicts that must be detected

## Required Actions

1. Navigate to Rehearsal_Schedule sheet
2. Insert a new column for conflict detection (e.g., "Has_Conflict")
3. Create formula that:
   - Cross-references Actor_Availability sheet
   - Checks if any assigned actor is unavailable on the rehearsal date
   - Returns "CONFLICT" or "OK" (or TRUE/FALSE)
4. Copy formula down to all rehearsal rows
5. (Optional but recommended) Apply conditional formatting to highlight conflicts
6. Save the file

## Success Criteria

1. ✅ **Conflict Column Present**: New column added with conflict indicators
2. ✅ **Formulas Used**: Uses formulas (not hardcoded values) with cross-sheet references
3. ✅ **High Recall**: Detects ≥90% of true conflicts (catches most/all problems)
4. ✅ **Good Precision**: ≥85% precision (few false alarms)
5. ✅ **Visual Highlighting**: Conditional formatting or highlighting applied

**Pass Threshold**: 70% (requires good conflict detection with formula-based approach)

## Skills Tested

- Multi-sheet navigation
- Cross-sheet cell references (e.g., `'Actor_Availability'.B2`)
- Logical functions (IF, AND, OR, COUNTIF, COUNTIFS)
- Lookup functions (VLOOKUP, INDEX/MATCH)
- Conditional formatting
- Data validation and quality assurance

## Formula Approaches

**Approach 1: COUNTIFS** (Recommended)