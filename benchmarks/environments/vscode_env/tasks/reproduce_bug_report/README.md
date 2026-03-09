# Bug Reproduction Task

**Difficulty**: 🟡 Medium  
**Skills**: Bug reproduction, technical documentation, terminal usage, file creation  
**Duration**: 180 seconds  
**Steps**: ~30

## Objective

Reproduce a reported bug by reading a bug report, creating test data that triggers the issue, running the problematic script, and documenting comprehensive reproduction steps.

## Expected Workflow

1. Read BUG_REPORT.txt to understand the issue
2. Create test_bug_input.csv with CSV data containing empty numeric fields
3. Open integrated terminal (Ctrl+`)
4. Run: `python data_processor.py test_bug_input.csv`
5. Observe the error that occurs
6. Create REPRODUCTION.md documenting:
   - Bug description
   - Numbered reproduction steps
   - Expected vs actual behavior
   - Complete error message/stack trace

## Verification

Checks for:
1. Test CSV file exists with proper structure
2. CSV contains empty fields (problematic pattern)
3. Reproduction document exists
4. Document contains clear steps
5. Document contains error message
6. Document includes execution command
7. Overall documentation quality

**Pass Threshold**: 70% (requires test file + documentation with steps and error)