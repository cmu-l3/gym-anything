# Analyze Production Logs Task

**Difficulty**: 🟡 Medium  
**Skills**: Log analysis, debugging, code navigation, error investigation  
**Duration**: 300 seconds  
**Steps**: ~80

## Objective

Analyze a production error log file to identify a critical failure, locate the problematic code line from the stack trace, and document the issue with a TODO comment.

## Scenario

You are the on-call engineer for a payment processing service. The system has been failing for the past hour, blocking user transactions. A production log file has been exported for analysis.

**Your mission:**
1. Open and analyze `/home/ga/workspace/logs/payment_service.log` 
2. Find the CRITICAL error causing payment failures (among 800+ log lines)
3. Extract the file path and line number from the error's stack trace
4. Navigate to that exact location in the source code
5. Add a TODO comment documenting the error for your team

## Expected Workflow

1. Open log file: `/home/ga/workspace/logs/payment_service.log`
2. Search for ERROR or critical issues (Ctrl+F)
3. Identify the AttributeError with stack trace
4. Note the file and line: `src/payment_processor.py:127`
5. Open that file (Ctrl+P or Explorer)
6. Navigate to line 127 (Ctrl+G)
7. Add TODO comment above or at the line
8. Save the file (Ctrl+S)

## Verification

Checks for:
1. TODO comment exists in payment_processor.py
2. TODO is at or near line 127 (±2 lines tolerance)
3. TODO mentions relevant error context (error type, api_key, production, etc.)

**Pass Threshold**: 100% for correct location + context, 70% for correct location only, 30% for TODO anywhere

## Real-world Skills Tested

- Production incident response
- Log file analysis and filtering
- Stack trace interpretation
- Code navigation (Go to File, Go to Line)
- Documentation and handoff to team