# Reproduce CI-Only Failure Task

**Difficulty**: 🟡 Medium  
**Skills**: Debugging, async/threading, test reliability, CI/CD troubleshooting  
**Duration**: 240 seconds  
**Steps**: ~60

## Objective

Fix a flaky test that passes locally but intermittently fails in CI by identifying and resolving a race condition.

## Scenario

A payment processing test is blocking the CI pipeline—it passes consistently on local machines but fails ~40% of the time in CI with timeout errors. The test uses a fixed `time.sleep(2)` to wait for asynchronous processing, which creates a race condition under different execution environments.

## Expected Workflow

1. Review the failing test in `tests/test_payment.py`
2. Examine the CI failure log to understand the pattern
3. Identify the race condition (async thread processing + fixed sleep)
4. Replace fixed sleep with proper polling logic
5. Add timeout mechanism (5-10 seconds recommended)
6. Include comment explaining the fix
7. Save the file

## Root Cause

The `PaymentProcessor.submit()` method spawns a background thread that takes variable time (0.1 + random 0-1.5 seconds). A fixed `time.sleep(2)` doesn't guarantee completion, especially under CI load.

## Expected Fix Pattern
