# Task: fix_failing_tests

## Overview

A common real-world scenario: a developer has written a BubbleSort implementation and a test suite, but the tests fail. The implementation is correct — the bugs are in the test file itself. This mirrors the frequent professional experience of debugging broken tests, which requires understanding JUnit mechanics, assertion method semantics, and test execution behavior.

**Domain**: Software quality assurance / Java unit testing
**Top occupations**: Software QA Analysts (ONET importance 99), Software Developers (90), Computer Programmers (99)

## Goal

Fix all test failures in `BubbleSortTest.java` so that all **four test methods** run and pass. The `BubbleSort.java` implementation is correct and must not be modified.

## Starting State

- IntelliJ IDEA is open with the `fix-failing-tests` Maven project loaded
- Running `BubbleSortTest` produces: 3 test failures + 1 test that silently never runs
- The `BubbleSort.java` source file is correct
- The bugs are exclusively in `BubbleSortTest.java`

## Agent Workflow

1. Open the project and run the test suite to see which tests fail
2. For each failure, read the error message and diagnose the root cause
3. Fix each bug independently in `BubbleSortTest.java`
4. Re-run the tests to confirm all 4 methods execute and pass
5. Ensure `BubbleSort.java` is unmodified

## Success Criteria (100 points)

| Criterion | Points | How Verified |
|-----------|--------|--------------|
| All 4 test methods annotated with @Test | 20 pts | Test report shows tests=4 |
| 0 test failures | 25 pts | Surefire report failures=0 |
| 0 test errors | 25 pts | Surefire report errors=0 |
| Array comparison uses assertArrayEquals | 15 pts | Source code pattern check |
| BubbleSort.java unmodified | 15 pts | MD5 checksum comparison |
| VLM: IntelliJ test runner visible | up to +10 pts | Trajectory analysis |

**Pass threshold**: ≥70 points AND all tests pass

## Verification Strategy

- `export_result.sh` runs `mvn test` and reads the Surefire XML report
- `verifier.py` checks test count, failure count, source patterns, and file integrity
- Adversarial protection: baseline checksum of BubbleSort.java ensures it was not modified

## Known Issues / Edge Cases

- JUnit 4's `assertEquals(Object, Object)` uses `Object.equals()` — arrays are compared by reference, not content
- A test method without `@Test` is silently ignored (not counted in surefire report)
- The return value of `sort()` must be captured — the method returns a new array, the original is unchanged
