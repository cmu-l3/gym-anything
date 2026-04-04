# Bypass Formatting Commits Task

**Difficulty**: 🟡 Medium  
**Skills**: Git blame, git archaeology, configuration, terminal commands, investigation  
**Duration**: 300 seconds  
**Steps**: ~35

## Objective

Configure Git to ignore mass formatting commits when running blame, then identify who actually modified business logic in a pricing calculation function.

## Scenario

You're debugging a discount calculation bug in `src/utils/pricing.js`. When you run `git blame`, every line shows "Intern Sam - Ran Prettier on entire codebase" from 2 weeks ago. The actual business logic changes are hidden behind formatting commits.

Your task is to use Git's `.git-blame-ignore-revs` feature to look through the formatting noise and find who really changed the pricing logic.

## Expected Workflow

1. Read `TASK_CONTEXT.md` for background
2. Try `git blame src/utils/pricing.js` (will show wrong author)
3. Run `git log --oneline` to identify formatting commits
4. Create `.git-blame-ignore-revs` file in project root
5. Add formatting commit hashes to the file
6. Run `git config blame.ignoreRevsFile .git-blame-ignore-revs`
7. Run `git blame src/utils/pricing.js` again (now shows real author)
8. Document findings in `INVESTIGATION_REPORT.txt`

## Verification

Checks for:
1. `.git-blame-ignore-revs` file created with commit hashes
2. File contains formatting commit hashes (ESLint and Prettier)
3. Git config `blame.ignoreRevsFile` set (optional bonus)
4. Investigation report exists
5. Report identifies Alice Chen as the author
6. Report contains correct commit hash (optional bonus)

**Pass Threshold**: 80% (4/4 critical checks)