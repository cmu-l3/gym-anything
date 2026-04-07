#!/bin/bash
echo "=== Exporting fix_subtitle_processor Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_subtitle_processor"
PROJECT_DIR="/home/ga/PycharmProjects/subtitle_processor"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Run Test Suite
echo "Running test suite..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

# 3. Analyze Test Results
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)

# Check specific bug fixes via test names
BUG1_PASS="false"
if echo "$PYTEST_OUTPUT" | grep -q "test_add_milliseconds_rollover PASSED"; then
    BUG1_PASS="true"
fi

BUG2_PASS="false"
if echo "$PYTEST_OUTPUT" | grep -q "test_convert_24_to_25_shrinks_duration PASSED"; then
    BUG2_PASS="true"
fi

BUG3_PASS="false"
if echo "$PYTEST_OUTPUT" | grep -q "test_parse_file_no_trailing_newline PASSED"; then
    BUG3_PASS="true"
fi

# 4. Static Analysis (Backup verification)

# Check Bug 1: timestamp.py should have logic to handle seconds >= 60
TIMESTAMP_FILE="$PROJECT_DIR/processor/timestamp.py"
BUG1_CODE_CHECK="false"
if grep -q "self.seconds >= 60" "$TIMESTAMP_FILE" || grep -q "divmod(self.seconds, 60)" "$TIMESTAMP_FILE"; then
    BUG1_CODE_CHECK="true"
fi

# Check Bug 2: converter.py should use source/target or 24/25 ratio logic
CONVERTER_FILE="$PROJECT_DIR/processor/converter.py"
BUG2_CODE_CHECK="false"
if grep -q "self.source_fps / self.target_fps" "$CONVERTER_FILE"; then
    BUG2_CODE_CHECK="true"
fi

# Check Bug 3: parser.py should append block after loop
PARSER_FILE="$PROJECT_DIR/processor/parser.py"
BUG3_CODE_CHECK="false"
if grep -q "if current_block:" "$PARSER_FILE" && grep -q "subtitles.append(current_block)" "$PARSER_FILE"; then
    # We need to make sure this is OUTSIDE the loop.
    # Simple grep isn't perfect but good indicator combined with tests.
    BUG3_CODE_CHECK="true"
fi

# 5. Create Result JSON
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed_count": $TESTS_PASSED,
    "tests_failed_count": $TESTS_FAILED,
    "bug1_test_pass": $BUG1_PASS,
    "bug2_test_pass": $BUG2_PASS,
    "bug3_test_pass": $BUG3_PASS,
    "bug1_code_check": $BUG1_CODE_CHECK,
    "bug2_code_check": $BUG2_CODE_CHECK,
    "bug3_code_check": $BUG3_CODE_CHECK
}
EOF

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="