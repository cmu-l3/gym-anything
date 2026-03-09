# Fix Timezone Handling Task

**Difficulty**: 🟡 Medium  
**Skills**: Code search, refactoring, Python datetime, debugging  
**Duration**: 300 seconds  
**Steps**: ~30

## Objective

Fix timezone handling bugs in a Python scheduling application by converting naive `datetime.now()` calls to timezone-aware `datetime.now(timezone.utc)` calls.

## Scenario

Your team's appointment scheduling app has bugs where meeting times display incorrectly for users in different timezones. The code uses naive datetime objects inconsistently. You need to fix the critical timezone bugs in `scheduler.py` and `models.py`.

## Expected Workflow

1. Open the workspace in VSCode (`/home/ga/workspace/scheduler_app/`)
2. Use Find in Files (Ctrl+Shift+F) to search for `datetime.now()`
3. Examine `scheduler.py` and `models.py` for naive datetime usage
4. Add `from datetime import timezone` import to files that need it
5. Replace `datetime.now()` with `datetime.now(timezone.utc)` in:
   - `create_appointment` function
   - `get_upcoming_appointments` function
   - `save_appointment` function
   - Any other locations with naive datetime.now()
6. Save all modified files (Ctrl+S)

## Files to Modify

- **scheduler.py**: Contains `create_appointment`, `get_upcoming_appointments`, `is_past_due` functions
- **models.py**: Contains `save_appointment`, `get_appointments` functions

## Verification

Checks for:
1. Timezone import added (`from datetime import timezone`)
2. At least 3 instances of `datetime.now(timezone.utc)` across both files
3. No naive `datetime.now()` calls remaining in critical functions
4. Proper code structure maintained

**Pass Threshold**: 75% (3/4 criteria)