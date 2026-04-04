#!/bin/bash
echo "=== Exporting create_flask_app result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/hello_flask"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check project structure
PROJECT_EXISTS="false"
APP_EXISTS="false"
TEST_EXISTS="false"
REQUIREMENTS_EXISTS="false"
TESTS_PASS="false"

APP_CONTENT=""
TEST_CONTENT=""
REQUIREMENTS_CONTENT=""
PYTEST_OUTPUT=""

if [ -d "$PROJECT_DIR" ]; then
    PROJECT_EXISTS="true"
fi

if [ -f "$PROJECT_DIR/app.py" ]; then
    APP_EXISTS="true"
    APP_CONTENT=$(cat "$PROJECT_DIR/app.py" 2>/dev/null)
fi

if [ -f "$PROJECT_DIR/test_app.py" ]; then
    TEST_EXISTS="true"
    TEST_CONTENT=$(cat "$PROJECT_DIR/test_app.py" 2>/dev/null)
fi

if [ -f "$PROJECT_DIR/requirements.txt" ]; then
    REQUIREMENTS_EXISTS="true"
    REQUIREMENTS_CONTENT=$(cat "$PROJECT_DIR/requirements.txt" 2>/dev/null)
fi

# Run pytest if tests exist
if [ "$TEST_EXISTS" = "true" ]; then
    cd "$PROJECT_DIR"
    # Install requirements first if they exist
    if [ -f requirements.txt ]; then
        pip3 install -r requirements.txt -q 2>/dev/null || true
    fi
    # Also ensure pytest is available
    pip3 install pytest -q 2>/dev/null || true

    # Run pytest and capture output AND exit code
    PYTEST_OUTPUT=$(python3 -m pytest test_app.py -v 2>&1)
    PYTEST_EXIT_CODE=$?

    # Check if all tests passed using exit code (more reliable than string parsing)
    # pytest exit codes: 0 = all tests passed, 1+ = failures/errors
    if [ $PYTEST_EXIT_CODE -eq 0 ]; then
        TESTS_PASS="true"
    fi
fi

# Escape content for JSON
APP_ESCAPED=$(echo "$APP_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
TEST_ESCAPED=$(echo "$TEST_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
REQ_ESCAPED=$(echo "$REQUIREMENTS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
PYTEST_ESCAPED=$(echo "$PYTEST_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Write result JSON
RESULT_JSON=$(cat << EOF
{
    "project_exists": $PROJECT_EXISTS,
    "app_exists": $APP_EXISTS,
    "test_exists": $TEST_EXISTS,
    "requirements_exists": $REQUIREMENTS_EXISTS,
    "tests_pass": $TESTS_PASS,
    "app_content": $APP_ESCAPED,
    "test_content": $TEST_ESCAPED,
    "requirements_content": $REQ_ESCAPED,
    "pytest_output": $PYTEST_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
