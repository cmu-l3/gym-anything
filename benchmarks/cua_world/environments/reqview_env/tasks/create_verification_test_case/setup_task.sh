#!/bin/bash
set -e
echo "=== Setting up Create Verification Test Case task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
PROJECT_PATH=$(setup_task_project "create_test_case")
echo "Project created at: $PROJECT_PATH"

# Record initial count of objects in TESTS document
TESTS_JSON="$PROJECT_PATH/documents/TESTS.json"
INITIAL_COUNT=0
if [ -f "$TESTS_JSON" ]; then
    # Simple grep count of "id" keys as a proxy for object count
    INITIAL_COUNT=$(grep -c "\"id\":" "$TESTS_JSON" || echo "0")
fi
echo "$INITIAL_COUNT" > /tmp/initial_test_count.txt
echo "Initial test count: $INITIAL_COUNT"

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

# Wait for window and maximize
maximize_window

# Dismiss dialogs
dismiss_dialogs

# Open the SRS document first (so the agent sees the source requirement)
open_srs_document

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="