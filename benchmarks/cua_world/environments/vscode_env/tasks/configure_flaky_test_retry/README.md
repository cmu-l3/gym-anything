# Configure Flaky Test Retry Task

**Difficulty**: 🟡 Medium  
**Skills**: Test configuration, debugging, documentation  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Configure Jest test runner to handle flaky tests by adding retry logic, increasing timeouts, and documenting the changes. This reflects a real-world scenario where tests fail intermittently and need tooling improvements before investigating root causes.

## Scenario

You're working on a Node.js project with a Jest test suite. Several tests fail intermittently (roughly 1 in 5 runs), particularly:
- `fetchUserData` - times out occasionally
- `processWebhook` - fails randomly due to async timing

Your task is to:
1. Configure Jest to retry failed tests automatically
2. Increase timeout for the `fetchUserData` test
3. Add retry logic for the `processWebhook` test
4. Add logging to track retry attempts
5. Document the flaky tests

## Expected Workflow

1. Open `jest.config.js` and add retry configuration
2. Open `tests/api.test.js` and modify:
   - Increase `fetchUserData` test timeout to 10000ms
   - Add retry annotation to `processWebhook` test
   - Add `console.log` to track attempts
3. Create `FLAKY_TESTS.md` to document the changes
4. Save all files

## Verification

Checks for:
1. Jest config has retry configuration (25 points)
2. `fetchUserData` timeout increased to ≥10000ms (20 points)
3. `processWebhook` has retry logic (15 points)
4. Logging statements added (15 points)
5. `FLAKY_TESTS.md` created with proper content (25 points)

**Pass Threshold**: 75% (75/100 points)