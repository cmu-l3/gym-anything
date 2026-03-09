# Triage Linting Errors Task

**Difficulty**: 🟡 Medium  
**Skills**: Error management, type hints, code quality, linting tools  
**Duration**: 480 seconds  
**Steps**: ~40

## Objective

Systematically triage and resolve linting errors in a Python project using VSCode's Problems panel. The workspace contains multiple Python files with various `pylint` and `mypy` errors that need to be fixed.

## Scenario

Your team just enabled strict type checking (`mypy --strict`) and comprehensive linting (`pylint`) in the CI pipeline. Your feature branch now has 40+ linting errors across 6 files, and the build is failing. You need to systematically fix these errors to get the PR merge-ready.

## Expected Workflow

1. Open workspace at `/home/ga/workspace/customer_portal/`
2. View Problems panel (View → Problems or Ctrl+Shift+M)
3. Review all Error-level items (ignore Warnings)
4. Fix errors systematically:
   - Add missing type hints (e.g., `: str`, `: int`, `-> None`)
   - Fix undefined variables
   - Fix incorrect return types
   - Fix import errors
   - Initialize unbound local variables
   - Add suppression comments for false positives (`# type: ignore`, `# pylint: disable=rule`)
5. Save all modified files (Ctrl+S or File → Save All)
6. Verify Problems panel shows 0 Errors (warnings are acceptable)

## Success Criteria

- All **Error-level** items removed from Problems panel
- At least **5 files** were modified
- Type hints added where missing
- At least one suppression comment added
- All files remain syntactically valid Python

## Files with Issues

- `src/models.py` - Missing type hints, unused imports
- `src/database.py` - Type errors, undefined variables
- `src/api_client.py` - Unbound local variables, missing annotations
- `src/validators.py` - Complex function, missing docstrings
- `src/utils.py` - Unused variables, naming conventions
- `tests/test_models.py` - Import errors

**Pass Threshold**: 70% (7/10 points)