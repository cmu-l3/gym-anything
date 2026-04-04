#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Evolve API Schema Results ==="

WORKSPACE_DIR="/home/ga/workspace/user-api"

# Focus VSCode and save all files
focus_vscode_window
{
    echo "Saving all files..."
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Failed to send save commands; continuing"
}

# Wait for files to be written
sleep 2

# Run pytest and export results
echo "Running pytest to verify backward compatibility..."
cd "$WORKSPACE_DIR"

# Test 1: Run existing test to verify backward compatibility
sudo -u ga bash -c "cd $WORKSPACE_DIR && source venv/bin/activate && python -m pytest tests/test_user_api.py::test_get_user_success -v --tb=short" > /tmp/test_existing_success.txt 2>&1
EXISTING_TEST_EXIT_CODE=$?
echo "Existing test exit code: $EXISTING_TEST_EXIT_CODE" >> /tmp/test_existing_success.txt

# Test 2: Run all tests
sudo -u ga bash -c "cd $WORKSPACE_DIR && source venv/bin/activate && python -m pytest tests/test_user_api.py -v --tb=short" > /tmp/test_all_tests.txt 2>&1
ALL_TESTS_EXIT_CODE=$?
echo "All tests exit code: $ALL_TESTS_EXIT_CODE" >> /tmp/test_all_tests.txt

# Test 3: Check if new test exists and run it specifically
if grep -q "def test_user_email_verified_field" "$WORKSPACE_DIR/tests/test_user_api.py" 2>/dev/null; then
    sudo -u ga bash -c "cd $WORKSPACE_DIR && source venv/bin/activate && python -m pytest tests/test_user_api.py::test_user_email_verified_field -v --tb=short" > /tmp/test_new_test.txt 2>&1
    NEW_TEST_EXIT_CODE=$?
    echo "New test exit code: $NEW_TEST_EXIT_CODE" >> /tmp/test_new_test.txt
else
    echo "New test function not found" > /tmp/test_new_test.txt
    echo "New test exit code: 1" >> /tmp/test_new_test.txt
fi

# Export file modification times
stat "$WORKSPACE_DIR/app/models.py" > /tmp/models_stat.txt 2>&1 || echo "File not found" > /tmp/models_stat.txt
stat "$WORKSPACE_DIR/app/schemas.py" > /tmp/schemas_stat.txt 2>&1 || echo "File not found" > /tmp/schemas_stat.txt
stat "$WORKSPACE_DIR/app/main.py" > /tmp/main_stat.txt 2>&1 || echo "File not found" > /tmp/main_stat.txt
stat "$WORKSPACE_DIR/tests/test_user_api.py" > /tmp/tests_stat.txt 2>&1 || echo "File not found" > /tmp/tests_stat.txt

echo "✅ Test results exported to /tmp"
echo "Workspace: $WORKSPACE_DIR"
ls -la "$WORKSPACE_DIR/app/" || true
ls -la "$WORKSPACE_DIR/tests/" || true