# Trace Error Source Task

**Difficulty**: 🟡 Medium  
**Skills**: Debugging, stack trace analysis, error investigation, defensive programming  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Investigate a production error by analyzing a stack trace, navigating to the source of the bug, documenting the root cause, and implementing a defensive fix.

## Scenario

A Python web service started throwing `AttributeError: 'NoneType' object has no attribute 'get'` errors in production. You have a captured error log in `error_output.txt`. Your task is to trace the error back to YOUR code (not library code), understand why it failed, and fix it.

## Expected Workflow

1. Open and read `error_output.txt` to analyze the stack trace
2. Identify the failing line in `data_processor.py` (line 67)
3. Navigate to the exact location in the code
4. Read the surrounding context to understand the bug
5. Create `investigation_notes.md` documenting:
   - The specific line that failed
   - Root cause analysis (what went wrong and why)
   - Proposed fix or workaround
6. Add explanatory comments in `data_processor.py` near the bug
7. Implement a defensive fix (add None check before calling `.get()`)

## Verification

Checks for:
1. `investigation_notes.md` exists with substantial content (>100 chars)
2. Investigation mentions line 67
3. Root cause documented (mentions None/NoneType/extract_address_info)
4. Explanatory comments added to `data_processor.py`
5. Defensive None check implemented
6. Fix is in the correct location (near line 67)
7. Investigation proposes a solution

**Pass Threshold**: 85% (6/7 criteria)