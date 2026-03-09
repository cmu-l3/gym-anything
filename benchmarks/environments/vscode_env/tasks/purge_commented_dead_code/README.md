# Purge Commented Dead Code Task

**Difficulty**: 🟡 Medium  
**Skills**: Code comprehension, pattern recognition, search/replace, multi-file editing  
**Duration**: 600 seconds  
**Steps**: ~100

## Objective

Clean up a Python project by removing commented-out dead code while preserving legitimate documentation comments and intentionally disabled code marked with TODO/FIXME/NOTE.

## Scenario

You inherited a legacy codebase where the previous developer habitually commented out old code instead of deleting it. Over time, hundreds of lines of commented functions, debug statements, and old implementations accumulated, making the code harder to read and review.

Your manager requested cleanup before the next sprint, but you must be careful not to delete:
- Docstrings ("""multiline strings""")
- Explanatory comments (e.g., "# Check for required fields")
- Intentionally disabled code marked with TODO/FIXME/NOTE

## Files to Clean
