#!/bin/bash
echo "=== Exporting refactor_sql_to_text_blocks result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/legacy-reporting"
TARGET_FILE="$PROJECT_DIR/src/main/java/com/reporting/ReportQuery.java"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Tests
echo "Running tests..."
TEST_OUTPUT_FILE="/tmp/maven_test_output.txt"
cd "$PROJECT_DIR"
# Run tests and capture output. Use || true so script doesn't exit on test failure.
su - ga -c "mvn test" > "$TEST_OUTPUT_FILE" 2>&1 || true

# Determine test result from output
TESTS_PASSED="false"
if grep -q "BUILD SUCCESS" "$TEST_OUTPUT_FILE"; then
    TESTS_PASSED="true"
fi

# 3. Read Source File Content
FILE_CONTENT=""
if [ -f "$TARGET_FILE" ]; then
    FILE_CONTENT=$(cat "$TARGET_FILE")
fi

# 4. Check for file modification (Anti-gaming)
FILE_MODIFIED="false"
INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null | awk '{print $1}')
CURRENT_HASH=$(md5sum "$TARGET_FILE" 2>/dev/null | awk '{print $1}')

if [ "$INITIAL_HASH" != "$CURRENT_HASH" ]; then
    FILE_MODIFIED="true"
fi

# 5. Create Result JSON
# Use python to safely escape strings for JSON
python3 << EOF
import json
import os

try:
    with open('$TARGET_FILE', 'r') as f:
        content = f.read()
except:
    content = ""

try:
    with open('$TEST_OUTPUT_FILE', 'r') as f:
        test_out = f.read()[-2000:] # Last 2000 chars
except:
    test_out = ""

result = {
    "file_content": content,
    "tests_passed": "$TESTS_PASSED" == "true",
    "file_modified": "$FILE_MODIFIED" == "true",
    "test_output_snippet": test_out,
    "timestamp": "$(date +%s)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="