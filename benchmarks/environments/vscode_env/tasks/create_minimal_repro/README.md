# Create Minimal Reproduction Task

**Difficulty**: 🟡 Medium  
**Skills**: Code comprehension, dependency analysis, file creation, documentation, simplification  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Extract a bug from a complex application into a minimal reproducible example suitable for reporting to library maintainers.

## Real-World Context

You've discovered a bug in the `python-dateutil` library while working on a complex web application. The library maintainers ask for a "minimal reproducible example" - not your entire 50-file application, just the smallest possible code that demonstrates the problem.

This is one of the most common activities when:
- Filing bugs on GitHub
- Asking for help on StackOverflow
- Debugging interactions between libraries
- Proving an issue is in external code, not yours

## Task Requirements

Create a new folder `/home/ga/workspace/bug-reproduction` containing:

### 1. `repro.py` (minimal reproduction script)
- Single Python file with < 20 lines of code
- Imports ONLY python-dateutil (no local imports like `utils`, `validators`)
- Contains the problematic date parsing code
- Includes a comment explaining the unexpected behavior
- Must be executable: `python repro.py`

### 2. `README.md` (documentation)
Must include these sections:
- Clear title describing the issue
- "Steps to Reproduce" section with exact commands
- "Expected Behavior" section
- "Actual Behavior" section
- Python version and OS information

### 3. `requirements.txt` (dependencies)
- Contains ONLY `python-dateutil==2.8.2`
- No other dependencies from the main application

## Expected Workflow

1. Explore the application in `/home/ga/workspace/myapp`
2. Identify the bug in `src/main.py` (line ~15)
3. Create new folder: `/home/ga/workspace/bug-reproduction`
4. Extract minimal code that reproduces the issue
5. Remove all unnecessary imports and code
6. Write clear documentation
7. Create minimal requirements.txt

## Verification Criteria

- ✅ Folder exists with exactly 3 files
- ✅ `repro.py` is minimal (< 20 lines)
- ✅ Only imports `dateutil`, no local imports
- ✅ Contains the date parsing bug code
- ✅ File is syntactically valid Python
- ✅ README has all required sections
- ✅ requirements.txt has single dependency with pinned version

**Pass Threshold**: 100% (all criteria must pass)

## Tips

- Strip away ALL business logic
- Remove config files, utils, validators
- Focus only on the dateutil parsing issue
- Make it runnable by someone with zero context
- Good minimal reproductions are < 15 lines