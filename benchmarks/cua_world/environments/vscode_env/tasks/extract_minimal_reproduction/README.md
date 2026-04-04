# Extract Minimal Reproducible Example Task

**Difficulty**: 🟡 Medium  
**Skills**: Code simplification, debugging, technical communication, isolation  
**Duration**: 300 seconds  
**Steps**: ~40

## Objective

Create a minimal reproducible example (MRE) from complex production code that demonstrates a bug in the `numpy-financial` library. The MRE should be clean, self-contained, and suitable for posting as a GitHub issue.

## Scenario

Your company's portfolio risk calculator has a bug where `npf.irr()` produces incorrect results when cash flows include very small values near zero (like `0.000001`). The production codebase is large and complex with internal dependencies that cannot be shared publicly. You need to create a minimal example that isolates just the bug.

## Expected Output

Create two files:

### 1. `bug_report_mre.py`
A minimal Python script (≤25 lines of code) that:
- Uses only `numpy` and `numpy_financial`
- Demonstrates the problematic behavior
- Includes comments explaining expected vs actual behavior
- Prints output showing the issue
- Is syntactically valid and can be run directly

### 2. `BUG_REPORT.md`
A bug report document containing:
- Clear title describing the issue
- Environment information (library versions)
- Expected behavior
- Actual behavior
- Steps to reproduce (how to run the MRE)
- Optional: Additional context

## Key Skills

- **Code simplification**: Remove business logic, keep bug essence
- **Dependency isolation**: Strip internal/unnecessary imports
- **Verification discipline**: Ensure the bug still reproduces
- **Technical communication**: Write clear, helpful documentation

## Verification

Checks for:
1. MRE file exists and is minimal (≤30 lines)
2. Only uses public dependencies (numpy, numpy_financial)
3. Contains problematic data pattern (small values)
4. Calls the buggy function (npf.irr)
5. Has sufficient documentation (≥3 comments)
6. Prints output to demonstrate the bug
7. Bug report markdown exists
8. Bug report has all required sections
9. MRE is syntactically valid Python
10. Business logic was successfully removed

**Pass Threshold**: 80% (8/10 criteria)