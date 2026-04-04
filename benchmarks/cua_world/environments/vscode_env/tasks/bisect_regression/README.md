# Bisect Regression Task

**Difficulty**: 🟡 Medium  
**Skills**: Git bisect, systematic debugging, version control, test execution  
**Duration**: 600 seconds  
**Steps**: ~40

## Objective

Use Git bisect to systematically identify which commit introduced a test regression in a payment processing service. The staging environment's integration test `test_payment_processing_idempotency` now fails 80% of the time, and you need to find the culprit commit among 47 recent commits.

## Scenario

You've returned from a 2-week vacation. During your absence, your team merged 47 commits across multiple feature branches. The integration test `test_payment_processing_idempotency` was 100% reliable before you left, but now fails frequently. Production deploy is scheduled for tomorrow, and you need to identify which commit broke it.

## Expected Workflow

1. Open VSCode integrated terminal (Ctrl+` or View → Terminal)
2. Navigate to `/home/ga/workspace/payment-service`
3. Start git bisect between `v2.3.0-pre-vacation` (good) and `HEAD` (bad)
4. At each bisect checkpoint, run the test: `npm test`
5. Mark commits as `good` or `bad` based on test results
6. Continue until git bisect identifies the first bad commit
7. Document findings in `BISECT_RESULTS.md` including:
   - Bad commit SHA
   - Commit message
   - Commit author
   - Files changed
   - Brief hypothesis about what broke
8. Run `git bisect reset` to clean up

## Git Bisect Commands
