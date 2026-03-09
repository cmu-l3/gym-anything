# Recover from Timeline Task

**Difficulty**: 🟡 Medium  
**Skills**: VSCode Timeline, local file history, disaster recovery, file comparison  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Recover a deleted function (`validate_headers`) from VSCode's Timeline view (local file history) after accidentally saving over working code.

## Scenario

You were refactoring `data_processor.py` and used Find & Replace with a regex that was too broad. It accidentally removed the critical `validate_headers()` function. You saved the file instinctively (Ctrl+S habit), losing your undo history. You haven't committed to Git yet. A teammate needs this function urgently.

## Expected Workflow

1. Open `/home/ga/workspace/data_processor.py` in VSCode
2. Notice the missing `validate_headers()` function (referenced in comments)
3. Open Timeline view:
   - Click Explorer sidebar (Ctrl+Shift+E)
   - Scroll down to "TIMELINE" section at the bottom
   - Or use View → Open View → Timeline
4. Select `data_processor.py` to see its history
5. Browse earlier Timeline entries (~5-10 minutes ago)
6. Right-click an earlier entry → "Compare with File" or "Open Timeline Item"
7. Locate the `validate_headers()` function in the historical version
8. Copy the function from the diff view or historical file
9. Paste it back into the current file (between `read_csv_file` and `transform_row`)
10. Save the file (Ctrl+S)

## What to Recover

The missing function should look like this:
