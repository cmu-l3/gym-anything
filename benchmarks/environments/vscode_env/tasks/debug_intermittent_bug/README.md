# Debug Intermittent Bug Task

**Difficulty**: 🟡 Medium  
**Skills**: Debugging, concurrency, diagnostic logging, documentation  
**Duration**: 300 seconds  
**Steps**: ~80

## Objective

Investigate a flaky integration test that fails intermittently due to a race condition in the database connection pool. Add diagnostic instrumentation and document findings.

## Scenario

You're a backend developer investigating a frustrating intermittent test failure. The integration test suite has a test that randomly fails with timeout errors. The test worked fine for weeks but started flaking after recent async changes. Your tech lead needs you to investigate and document what's happening.

## Expected Workflow

1. **Review the code**
   - Open `tests/integration/api_test.js` - the flaky test
   - Open `lib/database.js` - suspected issue location
   - Read `README.md` for context

2. **Add instrumentation**
   - Add `console.log()` statements to `lib/database.js`
   - Include timestamps (e.g., `Date.now()`)
   - Log connection pool state (activeConnections, queue.length)
   - Add at least 5 diagnostic log statements

3. **Run the test**
   - Open integrated terminal (Ctrl+`)
   - Run `npm test` multiple times
   - Observe pass/fail patterns
   - Capture log output

4. **Document findings**
   - Create `DEBUGGING_NOTES.md` in workspace root
   - Describe observed behavior
   - State suspected root cause
   - Include log snippets as evidence
   - Suggest potential fix (don't implement it)

5. **Save your work**
   - Save all modified files (Ctrl+S)

## Verification

Checks for:
1. At least 3 console.log statements added to database.js with timing/pool state info
2. DEBUGGING_NOTES.md exists with 200+ characters
3. Documentation mentions relevant concepts (race condition, connection pool, timeout, concurrency)
4. Documentation includes evidence (log snippets)

**Pass Threshold**: 75% (3/4 criteria)

## Tips

- Focus on `getConnection()` and `releaseConnection()` methods
- Look for race conditions when multiple requests arrive simultaneously
- Connection pool has max 5 connections - what happens with 10 concurrent requests?
- Don't fix the bug, just investigate and document