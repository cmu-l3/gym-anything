#!/bin/bash
echo "=== Setting up add_patient_order task ==="

# Source shared utilities (also checks service readiness)
source /workspace/scripts/task_utils.sh

rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Verify OpenELIS API is reachable
if ! wait_for_openelis 900; then
    echo "ERROR: OpenELIS is not reachable"
    exit 1
fi

# Record initial state for verification delta
INITIAL_SAMPLE_COUNT=$(openelis_db_query_count "SELECT COUNT(*) FROM clinlims.sample;")
echo "Initial sample count: $INITIAL_SAMPLE_COUNT"
echo "$INITIAL_SAMPLE_COUNT" > /tmp/initial_sample_count

INITIAL_SAMPLE_HUMAN_COUNT=$(openelis_db_query_count "SELECT COUNT(*) FROM clinlims.sample_human;")
echo "Initial sample_human count: $INITIAL_SAMPLE_HUMAN_COUNT"
echo "$INITIAL_SAMPLE_HUMAN_COUNT" > /tmp/initial_sample_human_count

# Start Firefox at the OpenELIS login page
if ! start_browser "$OPENELIS_LOGIN_URL" 4; then
    echo "ERROR: Browser failed to start cleanly"
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
    exit 1
fi

focus_browser || true
sleep 2

take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="
echo "Agent should see the OpenELIS login page."
echo "Task: Log in, create a new lab order for patient Wanjiku Njoroge with Glucose and Creatinine tests."
