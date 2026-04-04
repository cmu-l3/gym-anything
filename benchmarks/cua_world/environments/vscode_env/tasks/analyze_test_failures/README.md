# Analyze Test Failures Task

**Difficulty**: 🟡 Medium  
**Skills**: Search, log analysis, text processing, information extraction  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Parse a massive test output log file (8,000+ lines) to identify all failed tests and create an organized summary report.

## Scenario

You just ran the integration test suite for a large Python microservices project. The test run took 15 minutes and generated a massive log file (`test_output.log`) with 8,000+ lines containing verbose output from multiple test runners, database queries, HTTP requests, and stack traces. 

Your team lead urgently needs a summary of which specific tests failed and their error categories to triage for the sprint review in 30 minutes.

## Expected Workflow

1. Open the log file `/home/ga/workspace/test_output.log` (already open in VSCode)
2. Use VSCode search features (Ctrl+F, Find in Files, regex search) to identify failed tests
3. Failed tests follow the pattern: `FAILED test_module.py::test_function_name`
4. Extract all failed test names
5. Categorize by error type (AssertionError, TimeoutError, ConnectionError, etc.)
6. Create summary at `/home/ga/workspace/test_failures_summary.txt`
7. Summary should be concise (<100 lines) and well-organized

## Challenges

- Log contains ~8,200 lines with lots of noise (debug logs, queries, stack traces)
- Some log lines contain "ERROR" but aren't actual test failures (false positives)
- Need to extract information and organize it clearly
- Multiple error types need categorization

## Verification

Checks for:
1. All 12 failed tests identified
2. No false positives included
3. Error types categorized
4. Summary is well-organized
5. File is concise (<100 lines)

**Pass Threshold**: 75% (finding most failures with good organization)