#!/bin/bash
echo "=== Setting up configure_leave_type task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Sentrifugo to be accessible
wait_for_http "$SENTRIFUGO_URL" 60

# Record baseline leave type count
BASELINE_COUNT=$(get_leave_type_count)
log "Baseline leave type count: $BASELINE_COUNT"

# Ensure 'Bereavement Leave' does NOT exist (cleanup from prior run)
sentrifugo_db_root_query "DELETE FROM main_employeeleavetypes WHERE leavetype='Bereavement Leave';" 2>/dev/null || true

# Save baseline data for verification
safe_write_result "{\"baseline_leave_type_count\": ${BASELINE_COUNT:-0}}" /tmp/task_baseline.json

# Log in and navigate to Leave Types page
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/employeeleavetypes"

# Take screenshot of starting state
sleep 3
take_screenshot /tmp/task_start_screenshot.png

log "Task start state ready: Leave Types page visible"
echo "=== configure_leave_type task setup complete ==="
