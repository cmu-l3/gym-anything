# Git Bisect Payment Regression Task

**Difficulty**: 🟡 Medium  
**Skills**: Git bisect, debugging, version control, testing workflow  
**Duration**: 180 seconds  
**Steps**: ~30

## Objective

Use Git bisect to identify which commit introduced a regression in the payment validation module. A Visa card validator that worked in v2.3.0 now fails in v2.4.0. Find the exact commit that broke it.

## Scenario

You're investigating a critical bug: valid Visa cards starting with "4532" are being rejected. This worked two weeks ago (v2.3.0-release) but is broken now (v2.4.0-current). There are 23 commits between them. Use Git bisect to pinpoint the culprit.

## Expected Workflow

1. Navigate to `/home/ga/workspace/payment-service/`
2. Open integrated terminal (Ctrl+` or Terminal → New Terminal)
3. Start Git bisect: `git bisect start`
4. Mark current HEAD as bad: `git bisect bad v2.4.0-current`
5. Mark old version as good: `git bisect good v2.3.0-release`
6. For each commit Git checks out:
   - Run test: `./run_test.sh`
   - If test passes (exit 0): `git bisect good`
   - If test fails (exit 1): `git bisect bad`
7. Git will identify the first bad commit
8. Save bisect log: `git bisect log > /home/ga/workspace/bisect_result.txt`
9. End bisect: `git bisect reset`

## Verification

Checks for:
1. Bisect result file exists
2. Bisect log contains proper good/bad markings
3. Correct culprit commit identified (commit with "Refactor Visa validation")
4. Git bisect session was properly terminated

**Pass Threshold**: 100% (all criteria must pass)