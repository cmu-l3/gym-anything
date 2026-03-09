# Review PR Locally Task

**Difficulty**: 🟡 Medium  
**Skills**: Git branch checkout, code inspection, diff analysis, documentation, code review workflow  
**Duration**: 240 seconds  
**Steps**: ~80

## Objective

Check out a pull request branch locally, inspect the code changes, and document your review findings in a structured format.

## Scenario

Your teammate submitted a PR claiming to fix "the user input sanitization bug in the authentication module." Before approving, you need to review the changes locally to understand what was actually fixed.

## Expected Workflow

1. Use Git commands to checkout the PR branch `fix/sanitize-user-input`
2. Inspect which files were changed (Git diff, status, or file comparison)
3. Open and examine the key files containing the fix
4. Create a review summary file documenting your findings
5. Include: branch name, modified files, description of fix, test updates

## Verification

Checks for:
1. Correct branch checked out (`fix/sanitize-user-input`)
2. Review notes file created (`pr_review_notes.txt`)
3. Notes mention branch name
4. Notes identify key changed files (validator.py)
5. Notes mention test updates
6. Notes describe the nature of the fix

**Pass Threshold**: 80/100 (must have core elements: branch checkout + review file with key details)