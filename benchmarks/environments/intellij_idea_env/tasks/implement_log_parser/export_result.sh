#!/bin/bash
echo "=== Exporting implement_log_parser result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/log-analyzer"
RESULT_JSON="/tmp/task_result.json"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Run Tests (Programmatic Verification)
echo "Running tests..."
cd "$PROJECT_DIR"
mvn test > /tmp/maven_test_output.log 2>&1
COMPILE_EXIT_CODE=$?

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

if [ -d "$PROJECT_DIR/target/surefire-reports" ]; then
    for report in "$PROJECT_DIR/target/surefire-reports"/*.xml; do
        if [ -f "$report" ]; then
            run=$(grep -oP 'tests="\K[0-9]+' "$report" | head -1 || echo 0)
            fail=$(grep -oP 'failures="\K[0-9]+' "$report" | head -1 || echo 0)
            err=$(grep -oP 'errors="\K[0-9]+' "$report" | head -1 || echo 0)
            skip=$(grep -oP 'skipped="\K[0-9]+' "$report" | head -1 || echo 0)
            
            TESTS_RUN=$((TESTS_RUN + run))
            TESTS_FAILED=$((TESTS_FAILED + fail + err))
            TESTS_SKIPPED=$((TESTS_SKIPPED + skip))
        fi
    done
    TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED - TESTS_SKIPPED))
fi

# 3. Check Report File (File-based Verification)
REPORT_FILE="$PROJECT_DIR/output/report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE")
fi

# 4. Capture Implementation Source (Code Inspection)
PARSER_SOURCE=""
ANALYZER_SOURCE=""

if [ -f "$PROJECT_DIR/src/main/java/com/loganalyzer/LogParser.java" ]; then
    PARSER_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/loganalyzer/LogParser.java")
fi

if [ -f "$PROJECT_DIR/src/main/java/com/loganalyzer/LogAnalyzer.java" ]; then
    ANALYZER_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/loganalyzer/LogAnalyzer.java")
fi

# 5. Escape content for JSON safely using python
python3 -c "
import json
import os
import sys

def safe_read(path):
    try:
        with open(path, 'r', errors='replace') as f:
            return f.read()
    except:
        return ''

result = {
    'compile_success': ${COMPILE_EXIT_CODE} == 0,
    'tests_run': ${TESTS_RUN},
    'tests_passed': ${TESTS_PASSED},
    'tests_failed': ${TESTS_FAILED},
    'report_exists': '${REPORT_EXISTS}' == 'true',
    'report_content': sys.argv[1],
    'parser_source': sys.argv[2],
    'analyzer_source': sys.argv[3],
    'timestamp': '$(date -Iseconds)'
}

with open('${RESULT_JSON}', 'w') as f:
    json.dump(result, f)
" "$REPORT_CONTENT" "$PARSER_SOURCE" "$ANALYZER_SOURCE"

echo "Result exported to ${RESULT_JSON}"