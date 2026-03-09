# Triage Production Logs Task

**Difficulty**: 🟡 Medium  
**Skills**: Log analysis, regex search, pattern extraction, incident response, text analysis  
**Duration**: 240 seconds  
**Steps**: ~80

## Objective

Analyze a large production log file (8,000+ lines) from a payment service experiencing failures. Extract critical information and create a structured triage summary to help the on-call engineer respond to the incident.

## Scenario

**Context**: 3 AM production incident. The payment service is experiencing intermittent failures. Your task is to analyze the logs and create an actionable triage summary before the morning traffic rush.

## Expected Workflow

1. Open `production_payment_service.log` in VSCode
2. Use Find/Search (Ctrl+F) with regex to locate ERROR and CRITICAL entries
3. Extract affected transaction IDs (format: `txn_XXXXXXXXXXXX`)
4. Identify error patterns (error codes like `ERR_PAYMENT_TIMEOUT`, `ERR_INVALID_CARD`)
5. Count occurrences of each error type
6. Create `triage_summary.md` with:
   - Error type counts
   - List of affected transaction IDs
   - Incident timeline
   - Patterns and recommendations

## Tips

- Use regex search: `\[ERROR\]|\[CRITICAL\]` to filter log levels
- Use "Find All" (Ctrl+Shift+F) for workspace-wide search
- Transaction ID pattern: `txn_\d{12}`
- Copy filtered results to new file for analysis
- Structure your summary with clear sections

## Verification

Checks for:
1. `triage_summary.md` file exists and is substantial (>500 chars)
2. Contains at least 10 unique transaction IDs
3. Transaction IDs are real (not fabricated)
4. Error counts are accurate (within ±10% of actual)
5. At least 3 different error types identified
6. Proper structure with sections/headers
7. Most common error type is correctly identified

**Pass Threshold**: All critical criteria met (100% on accuracy, structure, and completeness)