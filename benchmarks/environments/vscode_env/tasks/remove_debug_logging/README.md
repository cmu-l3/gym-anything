# Remove Debug Logging Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-file search, Find/Replace, pattern recognition, careful editing  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Remove all temporary debug `print()` statements from a Python project while preserving legitimate logging code and test output.

## Scenario

You were debugging a race condition in a data processing pipeline. To trace execution flow, you added `print()` statements with "DEBUG:" prefix throughout the codebase. The bug is now fixed, but these temporary debug prints must be removed before committing—your code review bot will reject the PR if any remain.

## Context & Constraints

**Files with debug prints to REMOVE** (20 total):
- `src/processor.py` (6 debug prints)
- `src/worker.py` (6 debug prints)
- `src/config.py` (4 debug prints)
- `src/utils.py` (4 debug prints)

**Files with legitimate code to PRESERVE**:
- `src/logger.py` - Contains legitimate logging functions with `print()` statements (KEEP ALL)
- `tests/test_processor.py` - Contains test output prints (KEEP ALL)

## Expected Workflow

1. Open Find in Files (Ctrl+Shift+F)
2. Search for debug prints: `print.*DEBUG` or similar pattern
3. Review results to understand scope (~20 occurrences)
4. Filter results to exclude `logger.py` and `tests/`
5. Either:
   - Use "Replace in Files" carefully with empty replacement
   - OR manually open each file and delete debug print lines
6. Verify no debug prints remain in `src/*.py` (except `logger.py`)
7. Verify `logger.py` and test files are untouched
8. Save all modified files (Ctrl+K S)

## Verification

Checks for:
1. All debug prints removed from application files (0 remaining)
2. Legitimate logging in `logger.py` preserved (5 prints)
3. Test file prints preserved
4. Functions not accidentally deleted

**Pass Threshold**: 100% - all debug prints removed, legitimate code preserved