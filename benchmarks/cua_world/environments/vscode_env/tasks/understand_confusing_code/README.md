# Code Archaeology Task: Understanding Historical Context

**Difficulty**: 🟡 Medium  
**Skills**: Git blame, commit history, code investigation, documentation  
**Duration**: 480 seconds  
**Steps**: ~40

## Objective

Investigate confusing code in `src/pricing/discount.js` to understand its historical context and determine if it's safe to refactor. Use Git tools to perform "code archaeology" and document your findings.

## Scenario

You found a function `calculateDiscount()` that has bizarre logic: it divides by 0.95 then immediately multiplies by 0.95, which looks like a no-op. Before "fixing" it, you need to understand WHY it was written this way.

## Expected Workflow

1. Open the workspace in VSCode (`/home/ga/workspace/pricing-project`)
2. Navigate to `src/pricing/discount.js` and examine the confusing code
3. Use **Git Blame** (right-click file → "Git: View File History" or timeline view)
4. Find the commit that introduced this code
5. Read the commit message to understand context
6. Check for related issues in `.github/issues/` directory
7. Review test files in `tests/` for edge cases
8. Create a file `INVESTIGATION.md` in the workspace root documenting:
   - The commit hash where the code was introduced
   - The author's name
   - Why this code exists (the leap year/timezone bug context)
   - Your recommendation: "SAFE_TO_REFACTOR" or "DO_NOT_CHANGE"

## Verification

Checks for:
1. `INVESTIGATION.md` file exists and has substantial content
2. Contains correct commit hash (a3f82b4...)
3. Mentions the author (Sarah Chen)
4. Explains the leap year/timezone bug context
5. Makes correct recommendation (DO_NOT_CHANGE - data migration not done yet)

**Pass Threshold**: 80% (4/5 criteria)

## Tips

- Use Source Control panel (Ctrl+Shift+G) to explore history
- Right-click on file → "Git: View File History"
- Check TODO/FIXME comments for issue references
- Read the `.github/issues/247.txt` file for full context
- Remember: sometimes "obviously wrong" code has good reasons!