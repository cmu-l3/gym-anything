# DIY Project Sequencer Task

**Difficulty**: 🟡 Medium  
**Skills**: Dependency logic, conditional formulas, timeline calculation  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Organize a multi-step bathroom renovation project by validating task dependencies, calculating timeline, and identifying sequencing errors. A homeowner has listed tasks in random order but doesn't know if the sequence is logical (e.g., can't install tile before waterproofing). The agent must add validation columns using formulas to check prerequisites, calculate start times, and flag violations.

## Task Description

Marcus is renovating his bathroom and has created a spreadsheet with 12 tasks, but he's confused about the proper order. Some tasks MUST happen before others (can't tile before waterproofing, can't paint before ventilation fan is installed).

The agent must:
1. Open the provided bathroom_renovation.ods file with task data
2. Add a "Dependency Check" column (F) with formulas to validate prerequisites are scheduled before each task
3. Add an "Earliest Start (Day)" column (G) to calculate when each task can begin
4. Add a "Critical Path?" column (H) to identify tasks with no slack time
5. Calculate total project duration in a summary cell
6. Save the updated file

## Starting Data

The spreadsheet contains:
- **Column A**: Task Name (12 renovation tasks)
- **Column B**: Duration (days) - time each task takes
- **Column C**: Prerequisites - semicolon-separated list of prerequisite task names
- **Column D**: Proposed Sequence - Marcus's initial guess (1-12)
- **Column E**: Needs Plumber? (Yes/No)

## Required Actions

### 1. Add Dependency Check Column (F)
Create formulas that verify each task's prerequisites are scheduled BEFORE it (lower sequence number). Should return:
- "OK" if all prerequisites satisfied
- Warning message if violations exist

### 2. Add Earliest Start Column (G)
Calculate the earliest day each task can start based on:
- All prerequisite tasks completing first
- Sum of prerequisite durations
- For tasks with no prerequisites, earliest start is Day 1

### 3. Add Critical Path Column (H)
Identify tasks on the critical path (tasks that would delay project if delayed):
- "Yes" if on critical path
- "No" if has slack time

### 4. Calculate Total Duration
Add a summary cell (e.g., A15) showing total project days from start to completion.

## Expected Results

- **Column F**: Formulas checking dependencies (not just text)
- **Column G**: Calculated earliest start days based on prerequisite chains
- **Column H**: Critical path identification
- **Summary Cell**: Total duration calculation
- **Violation Detection**: Task 8 (Paint walls) should be flagged as it's scheduled before its prerequisite Task 7 (Install ventilation fan)

## Success Criteria

1. ✅ **Dependency Check Column**: Formula-based validation present for all tasks
2. ✅ **Earliest Start Column**: Correctly calculated based on prerequisite chains
3. ✅ **Critical Path Column**: Accurately identifies zero-slack tasks
4. ✅ **Total Duration**: Correct project completion time calculated
5. ✅ **Violation Detection**: Intentional dependency error is flagged
6. ✅ **No Formula Errors**: All cells calculate without #REF!, #VALUE! errors

**Pass Threshold**: 75% (4/6 criteria must pass)

## Skills Tested

- Conditional logic (IF, AND, OR functions)
- Lookup functions (VLOOKUP, MATCH)
- Cell referencing (absolute and relative)
- String handling (for prerequisite parsing)
- Mathematical calculations (timeline, durations)
- Logical reasoning (dependency validation)

## Tips

- Use IF statements to check if prerequisite sequence numbers are lower
- VLOOKUP can help find prerequisite information
- Handle multiple prerequisites by checking each one
- Earliest start = MAX(all prerequisite end times) + 1
- Critical path tasks have earliest start = actual scheduled start