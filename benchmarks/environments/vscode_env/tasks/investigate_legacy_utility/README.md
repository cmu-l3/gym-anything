# Investigate Legacy Utility Task

**Difficulty**: 🟡 Medium  
**Skills**: Git history analysis, code navigation, archaeology, documentation  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Conduct code archaeology investigation on a mysterious utility function `sanitize_user_input()` that appears across multiple files. Create a comprehensive report documenting its history, current state, and recommendations.

## Scenario

You've joined a Python web application team and discovered a utility function with slight variations scattered across the codebase. Comments reference "the 2019 injection bug" but no current team member remembers details. Before refactoring, you must understand the historical context.

## Expected Workflow

1. **Investigate Git History**
   - Use `git log --grep="sanitize\|injection"` to find relevant commits
   - Use `git blame` on files containing the function
   - Read commit messages to understand original purpose

2. **Navigate Code**
   - Use Find All References (Shift+F12) or Find in Files (Ctrl+Shift+F)
   - Locate all files containing `sanitize_user_input`
   - Identify variations in implementation

3. **Check Test Coverage**
   - Explore tests/ directory
   - Search for test functions covering this utility

4. **Create Report**
   - Create `/home/ga/workspace/ARCHAEOLOGY_REPORT.md`
   - Document historical context (when, why, who)
   - List current locations and variations
   - Discuss test coverage
   - Provide actionable recommendation

## Verification

Checks for:
1. Report file exists at correct location (15%)
2. Contains "Historical Context" section (25%)
3. References original 2019 security context (20%)
4. Identifies multiple file locations (20%)
5. Discusses test coverage (10%)
6. Provides actionable recommendation (10%)

**Pass Threshold**: 60% (score ≥ 0.6)