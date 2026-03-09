# Task: debug_logic_error

## Overview

A core software developer skill: using the debugger to trace execution of a failing algorithm and identify a subtle logic error. The BinarySearch class compiles cleanly and passes syntactic checks, but several tests fail at runtime because of a wrong loop condition. The agent must actually use IntelliJ's debugger — setting breakpoints, stepping through execution, observing variable values — to discover the bug.

**Domain**: Debugging / Algorithm correctness
**Top occupations**: Software Developers (ONET importance 90), Computer Programmers (99), Information Security Engineers (97)

## Goal

Fix the logic bug in `BinarySearch.java` so that all **9 tests** in `BinarySearchTest` pass. Do not modify `BinarySearchTest.java`.

## Starting State

- IntelliJ IDEA is open with the `debug-logic-error` Maven project loaded
- Running `BinarySearchTest` produces 4 failures: `testSearchLastElement`, `testSearchSingleElementFound`, and two others that depend on the search finding an element at the boundary
- The bug is in the `search()` method — a wrong loop condition causes the method to return -1 when only one candidate remains
- `countInRange()` works correctly and those tests pass

## Agent Workflow

1. Run the test suite to identify which tests fail
2. Open `BinarySearch.java` and examine the `search()` method
3. Set a breakpoint inside the `search()` method loop
4. Debug one of the failing tests; observe that when `left == right` and `arr[left] == target`, the loop exits without checking the value
5. Identify the incorrect operator in the loop condition
6. Fix the single-character bug
7. Re-run all tests to confirm all 9 pass

## Success Criteria (100 points)

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| All 9 tests pass (0 failures, 0 errors) | 40 pts | Surefire report |
| Loop condition changed from `<` to `<=` | 25 pts | Source code pattern check |
| BinarySearchTest.java unmodified | 15 pts | MD5 checksum |
| Project compiles (class files present) | 10 pts | .class file existence |
| VLM: debugger or test runner visible | up to +10 pts | Trajectory analysis |

**Pass threshold**: ≥70 points AND all 9 tests pass

## Verification Strategy

- `export_result.sh` runs `mvn test` and reads the Surefire XML report
- `verifier.py` checks test count, failure count, source code pattern (`left <= right`), and file integrity
- Do-nothing produces: score=0 (4 tests fail, source unchanged)

## Bug Details (for verifier, not disclosed to agent)

The bug is in `BinarySearch.java` line in `search()`:
```java
while (left < right) {    // WRONG
while (left <= right) {   // CORRECT
```
When `left == right`, there is exactly one candidate. The correct condition allows the loop to check it. With `<`, the loop exits when one candidate remains and the method incorrectly returns -1.
