# Debug Timezone Conversion Task

**Difficulty**: 🟡 Medium  
**Skills**: Debugging, Date/time handling, Code inspection, JavaScript  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Debug a timezone conversion bug in a Node.js scheduling application where meetings are displayed at incorrect times across timezones. Use VSCode's debugger to identify where double timezone conversion occurs and mark the problematic code.

## Scenario

You're a developer on a meeting scheduling app. QA reports: "Meetings scheduled by East Coast users show 3 hours late for West Coast users." This is a classic timezone bug where date conversion is being applied twice.

## Expected Workflow

1. Open the workspace at `/home/ga/workspace/meeting-scheduler/`
2. Run the test script to see the bug (`npm test` or run `test/timezone-bug.js`)
3. Open `utils/dateConverter.js` to examine the conversion logic
4. Use VSCode debugger to step through the `localToUTC` function
5. Set breakpoints and inspect date values at runtime
6. Identify the line where double timezone conversion occurs
7. Add a comment marking the bug (e.g., `// BUG: Double timezone conversion here`)
8. Save the file (Ctrl+S)

## The Bug

The `localToUTC` function in `utils/dateConverter.js` applies timezone offset conversion twice:
1. `moment.tz(localTimeStr, timezone)` already interprets the string in the given timezone
2. The code then manually subtracts the `utcOffset` again, causing double conversion

## Verification

Checks for:
1. File `utils/dateConverter.js` exists and was opened
2. File was modified (has changes)
3. A bug marker comment was added (BUG, TODO, FIXME, or similar)
4. The marker is within 3 lines of the problematic code

**Pass Threshold**: 
- 100%: All criteria met, marker near bug location
- 70%: Marker added but not in optimal location
- 50%: File modified but no clear marker
- 20%: File opened but not modified

## Tips

- Use the integrated terminal to run `npm test` and see the bug output
- Use F5 to start debugging with the pre-configured launch configuration
- Set breakpoints in `utils/dateConverter.js` to inspect values
- Watch the `utcOffset` and `utcTimestamp` variables
- The bug is in the `localToUTC` function around line 15-17