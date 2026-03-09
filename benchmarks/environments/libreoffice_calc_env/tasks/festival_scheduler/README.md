# LibreOffice Calc Film Festival Scheduler Task (`festival_scheduler@1`)

## Overview

This task challenges an agent to clean messy film duration data and create a viable screening schedule for a small independent film festival. The agent must standardize duration formats (minutes, HH:MM, text descriptions), calculate total time blocks including Q&A buffers, and assign films to available time slots across two screening venues while avoiding overlaps and respecting venue capacity constraints.

## Rationale

**Why this task is valuable:**
- **Real-world Data Cleaning:** Tests ability to handle inconsistent input formats that plague real spreadsheets
- **Time Calculation Skills:** Requires understanding duration arithmetic and format conversions
- **Multi-constraint Scheduling:** Balances venue availability, film length, and buffer times
- **Practical Problem-Solving:** Represents common coordination task faced by event organizers
- **Formula Complexity:** Combines TEXT functions, time arithmetic, conditional logic, and lookups
- **Workflow Authenticity:** Reflects actual messiness of volunteer-run community events

**Skill Progression:** This intermediate task combines data cleaning, time manipulation, and logical assignment—essential skills for coordinating schedules, managing resources, and organizing multi-part events.

## Skills Required

### A. Interaction Skills
- **Data Standardization:** Convert mixed format durations into consistent representation
- **Formula Creation:** Build multi-step formulas combining text parsing, time arithmetic, and conditionals
- **Time Arithmetic:** Add durations and buffer times correctly
- **Conditional Assignment:** Use IF/AND/OR logic to determine venue assignments
- **Data Validation:** Identify and flag scheduling conflicts
- **Range References:** Work across multiple data ranges for lookups and comparisons

### B. LibreOffice Calc Knowledge
- **Time Functions:** Use TIME(), HOUR(), MINUTE(), TEXT() for time manipulation
- **Text Functions:** Use LEFT(), RIGHT(), MID(), FIND() to parse duration strings
- **Conditional Functions:** Apply IF(), AND(), OR() for logic
- **Lookup Functions:** Use VLOOKUP() or INDEX/MATCH for venue capacity checking
- **Time Formatting:** Understand Calc's internal time representation (decimal days)
- **Formula Debugging:** Troubleshoot errors in complex nested formulas

### C. Task-Specific Skills
- **Format Recognition:** Identify which duration format each entry uses
- **Domain Knowledge:** Understand typical Q&A buffer times (15-20 min) and transition periods
- **Constraint Awareness:** Recognize venue time windows and capacity limits
- **Conflict Detection:** Identify time slot overlaps across venues
- **Schedule Optimization:** Assign films to minimize gaps while respecting constraints

## Task Steps

### 1. Initial Data Assessment
- Examine the provided CSV file containing film submissions
- Note the mixed duration formats: "90", "1:45", "about 105 minutes", "2h 10m"
- Review the venue constraints provided in a separate reference file

### 2. Duration Standardization Column
- Create a new column "Duration_Minutes" to standardize all durations into integer minutes
- Parse text descriptions ("about 105 minutes" → 105)
- Convert HH:MM format ("1:45" → 105)
- Handle abbreviated formats ("2h 10m" → 130)
- Use combination of TEXT functions and conditional logic

### 3. Total Time Block Calculation
- Create "Total_Block_Minutes" column
- Add film duration + 15 minutes Q&A + 5 minutes transition buffer
- Formula: `=Duration_Minutes + 20`
- Convert to HH:MM format for readability if desired

### 4. Venue Assignment Logic
- Create "Assigned_Venue" column
- Use conditional logic based on film length:
  - Films over 120 min → "Main Theater" (larger capacity)
  - Documentary shorts (under 45 min) → "Gallery Space"
  - All others → distribute to balance load
- Consider venue capacity constraints from reference table

### 5. Time Slot Assignment
- Create "Time_Slot" column
- Assign start times from available slots: 2:00 PM, 4:00 PM, 6:30 PM, 8:30 PM
- Ensure films fit within slot before next scheduled start
- Use conditional logic: `=IF(Total_Block_Minutes <= 110, "2:00 PM", IF(...))`

### 6. Conflict Detection
- Create "Conflict_Flag" column
- Identify if assigned time slot + duration exceeds venue availability
- Flag cases where multiple films assigned to same venue at same time
- Use COUNTIFS() to detect duplicates: `=IF(COUNTIFS(Venue_Range, Venue, Time_Range, Time_Slot) > 1, "CONFLICT", "OK")`

### 7. Schedule Validation
- Calculate total scheduled time per venue
- Verify no venue exceeds 8-hour maximum (2 PM - 10 PM window)
- Ensure all films are assigned without conflicts

### 8. Summary Statistics (Optional)
- Count films per venue
- Calculate average block time per venue
- Identify any unassigned films or conflicts requiring manual resolution

## Verification Strategy

### Verification Approach
The verifier uses **multi-criteria validation** combining format checking, arithmetic verification, and logical constraint satisfaction:

### A. Duration Standardization Check
- **Format Validation:** Confirms "Duration_Minutes" column contains only numeric values (integers)
- **Reasonable Range:** Validates all durations are between 20-180 minutes (plausible film lengths)
- **Conversion Accuracy:** Verifies correct conversion from mixed formats
- **Completeness:** Ensures no blank cells in Duration_Minutes for films with original durations

### B. Total Block Calculation Verification
- **Arithmetic Accuracy:** Verifies Total_Block_Minutes = Duration_Minutes + 20 (buffer time)
- **Formula Presence:** Confirms cells contain formulas, not hard-coded values
- **Consistency:** Checks all rows use the same calculation logic

### C. Venue Assignment Logic Check
- **Constraint Adherence:** Validates films >120 min assigned to "Main Theater"
- **Complete Assignment:** Verifies all films have a venue assignment (no blanks)
- **Valid Venues:** Confirms only allowed venue names used

### D. Time Slot Assignment Verification
- **Valid Slots:** Checks all time slots match allowed values (2:00 PM, 4:00 PM, 6:30 PM, 8:30 PM)
- **Fit Check:** Validates each film's Total_Block_Minutes fits before next scheduled slot
- **Distribution:** Ensures reasonable balance across time slots

### E. Conflict Detection Verification
- **Duplicate Detection:** Confirms no same venue + time combinations exist
- **Conflict-Free Schedule:** Validates schedule is actually conflict-free OR conflicts are properly flagged

### F. Structural Validation
- **Required Columns Present:** Duration_Minutes, Total_Block_Minutes, Assigned_Venue, Time_Slot
- **Data Integrity:** No #REF!, #VALUE!, or #DIV/0! errors in any formula cells
- **Format Preservation:** Original film data (title, genre, director) remains intact

### Verification Checklist
- ✅ **Duration Standardized:** All durations converted to numeric minutes (≥90% accuracy)
- ✅ **Time Blocks Calculated:** Total_Block_Minutes = Duration + 20 for all films (≥90% accuracy)
- ✅ **Venue Constraints Met:** Films >120 min in Main Theater, all venues assigned (≥90% valid)
- ✅ **Time Slots Valid:** All assignments use allowed slots and fit within time windows (≥90% valid)
- ✅ **Conflicts Handled:** Schedule is conflict-free OR conflicts properly detected
- ✅ **No Formula Errors:** All calculated cells contain valid formulas without errors

### Scoring System
- **100%:** All 6 criteria met perfectly with correct formulas and no conflicts
- **85-99%:** 5/6 criteria met, minor issues in one area
- **70-84%:** 4/6 criteria met, reasonable schedule but with notable gaps
- **50-69%:** 3/6 criteria met, partial completion with significant issues
- **0-49%:** <3 criteria met, inadequate scheduling or major formula errors

**Pass Threshold:** 70% (requires solid data cleaning, calculation accuracy, and basic scheduling logic)

## Technical Implementation

### Files Structure