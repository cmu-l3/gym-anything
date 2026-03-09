# Navigate Back After Definition Task

**Difficulty**: 🟢 Easy  
**Skills**: Navigation history, keyboard shortcuts, cursor position management  
**Duration**: 30 seconds  
**Steps**: ~10

## Objective

Return to the original editing location in `main.py` after having jumped to a function definition in `utils/helpers.py` using VSCode's "Go Back" navigation feature.

## Scenario

You were editing code in `main.py` when you pressed F12 to check a function definition. Now you're viewing `helpers.py` but need to get back to where you were actually working.

## Expected Workflow

1. Press `Alt+Left` to navigate back
   - OR -
2. Use menu: Go → Back

## Verification

Checks for:
1. Active file is `main.py` (not stuck in `helpers.py`)
2. Cursor is near the original work position (within ±2 lines)
3. Original marker comment still exists in file
4. No unintended file modifications

**Pass Threshold**: 75% (3/4 criteria)