#!/bin/bash
# Pre-task setup for add_leave_type task
# Removes 'Bereavement Leave' if it exists, navigates to Leave > Configure > Leave Types

echo "=== Setting up add_leave_type task ==="

source /workspace/scripts/task_utils.sh

wait_for_http "$ORANGEHRM_URL" 60

# Remove 'Bereavement Leave' if already present
EXISTING_ID=$(orangehrm_db_query "SELECT id FROM ohrm_leave_type WHERE name='Bereavement Leave' AND deleted=0 LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
if [ -n "$EXISTING_ID" ]; then
    log "Soft-deleting existing 'Bereavement Leave' leave type (id=$EXISTING_ID)..."
    orangehrm_db_query "UPDATE ohrm_leave_type SET deleted=1 WHERE id=${EXISTING_ID};" || true
fi

# Record initial leave type count
INITIAL_COUNT=$(get_leave_type_count)
log "Initial leave type count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/orangehrm_initial_leavetype_count.txt
chmod 666 /tmp/orangehrm_initial_leavetype_count.txt 2>/dev/null || true

# Navigate to Leave > Configure > Leave Types
TARGET_URL="${ORANGEHRM_URL}/web/index.php/leave/leaveTypeList"
ensure_orangehrm_logged_in "$TARGET_URL"

sleep 2
take_screenshot /tmp/task_start_state.png
log "Task start state screenshot saved"

echo "=== add_leave_type task setup complete ==="
echo "Target: Add leave type 'Bereavement Leave'"
