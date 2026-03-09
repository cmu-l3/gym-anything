# Run Failing Tests Task

**Difficulty**: 🟡 Medium  
**Skills**: Testing panel, pytest execution, test result interpretation  
**Duration**: 240 seconds  
**Steps**: ~30

## Objective

Identify and run failing unit tests in a Python project using VSCode's Testing panel. The project contains intentional bugs that cause test failures. Your goal is to execute the tests and understand which tests are failing, WITHOUT fixing the bugs.

## Scenario

You've just pulled the latest changes from the main branch. The CI/CD pipeline reports test failures, but you need to run the tests locally to see the detailed error messages and understand what went wrong.

## Expected Workflow

1. Open Testing panel (flask icon on Activity Bar, or View → Testing)
2. Wait for test discovery to complete (VSCode will find tests automatically)
3. Observe that some tests show red X icons (failed status)
4. Run at least one specific failing test by clicking the "Run Test" icon next to it
5. Examine the test output in the Terminal to understand the failure
6. Optionally: Run all tests to see the complete picture (2 failed, 3 passed)

## Test Suite Overview

The project contains:
- **src/calculator.py**: Calculator module with intentional bugs
- **tests/test_calculator.py**: 5 unit tests (2 will fail, 3 will pass)

**Failing Tests:**
- `test_subtract`: Expected result doesn't match actual (bug in subtract function)
- `test_divide`: Expected result doesn't match actual (bug in divide function)

**Passing Tests:**
- `test_add`: Addition works correctly
- `test_multiply`: Multiplication works correctly
- `test_power`: Exponentiation works correctly

## Verification

Checks for:
1. ✅ Tests were executed (pytest cache exists)
2. ✅ Correct test framework used (pytest)
3. ✅ Selective test running (individual tests, not just full suite)
4. ✅ Test failures detected (2 failures identified)
5. ✅ Source code preserved (bugs not fixed - task is about RUNNING tests)

**Pass Threshold**: 75% (4/5 criteria)

## Important Notes

- **DO NOT** modify the source code to fix the bugs
- **DO NOT** modify the test files
- Focus on RUNNING and INTERPRETING tests, not fixing them
- Use VSCode's Testing panel (not just terminal commands)
- Look for the red X icons indicating test failures