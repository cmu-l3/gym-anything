# Review Uncommitted Diff Task

**Difficulty**: 🟡 Medium  
**Skills**: Source Control, diff reading, code review, quality control, Git  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Use VSCode's integrated Source Control diff viewer to comprehensively review uncommitted changes across multiple files, remove debug code and temporary hacks, and create a review summary before committing.

## Scenario

A backend developer spent time debugging a race condition in a Python FastAPI service. While debugging, they added numerous `print()` statements, temporary log messages, and a hardcoded test value. Now that the bug is fixed, they need to review all changes to ensure they only commit the actual fix—not the debugging artifacts.

## Expected Workflow

1. Open Source Control panel (Ctrl+Shift+G)
2. Review each modified file by clicking on it to see the diff
3. Identify and remove debug code:
   - Debug `print()` statements in `api/routes/orders.py`
   - Hardcoded test value and prints in `api/services/payment.py`
4. Verify clean changes are preserved:
   - Logging improvements in `api/utils/logger.py`
   - New test case in `tests/test_orders.py`
5. Create a review summary document at `/home/ga/workspace/REVIEW_SUMMARY.md` documenting:
   - Files reviewed
   - Debug code removed
   - Clean changes ready to commit
   - Review status

## Files to Review

- `api/routes/orders.py` - Contains race condition fix + debug prints (CLEAN UP NEEDED)
- `api/services/payment.py` - Contains validation fix + hardcoded test value (CLEAN UP NEEDED)
- `api/utils/logger.py` - Clean logging improvements (KEEP AS-IS)
- `tests/test_orders.py` - New test case (KEEP AS-IS)

## Verification

Checks for:
1. All 4 files were reviewed (modification timestamps)
2. Debug code removed (no print/DEBUG statements in orders.py or payment.py)
3. Legitimate changes preserved (race condition fix, logging, tests intact)
4. Review summary document created with required sections
5. Workflow sequence correct (edits before summary, reasonable timing)

**Pass Threshold**: 75% (4/5 criteria)