#!/bin/bash
echo "=== Setting up add_employee task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for Sentrifugo to be accessible
wait_for_http "$SENTRIFUGO_URL" 60

# Record baseline employee count
BASELINE_COUNT=$(get_employee_count)
log "Baseline employee count: $BASELINE_COUNT"

# Ensure employee EMP021 does NOT exist (remove if present from prior run)
sentrifugo_db_root_query "DELETE FROM main_employees_summary WHERE employeeId='EMP021';" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_users WHERE employeeId='EMP021';" 2>/dev/null || true

# Save baseline data for verification
safe_write_result "{\"baseline_employee_count\": ${BASELINE_COUNT:-0}}" /tmp/task_baseline.json

# Log in and navigate to Employee list page
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/employee"

# Take screenshot of starting state
sleep 3
take_screenshot /tmp/task_start_screenshot.png

log "Task start state ready: Employee list page visible"
echo "=== add_employee task setup complete ==="
