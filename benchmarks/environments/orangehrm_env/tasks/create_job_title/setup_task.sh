#!/bin/bash
# Pre-task setup for create_job_title task
# Removes 'Cloud Architect' if it exists, navigates to Admin > Job Titles

echo "=== Setting up create_job_title task ==="

source /workspace/scripts/task_utils.sh

wait_for_http "$ORANGEHRM_URL" 60

# Remove 'Cloud Architect' if already present
EXISTING_ID=$(orangehrm_db_query "SELECT id FROM ohrm_job_title WHERE job_title='Cloud Architect' AND is_deleted=0 LIMIT 1;" 2>/dev/null | tr -d '[:space:]')
if [ -n "$EXISTING_ID" ]; then
    log "Soft-deleting existing 'Cloud Architect' job title (id=$EXISTING_ID)..."
    orangehrm_db_query "UPDATE ohrm_job_title SET is_deleted=1 WHERE id=${EXISTING_ID};" || true
fi

# Record initial job title count
INITIAL_COUNT=$(get_job_title_count)
log "Initial job title count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/orangehrm_initial_jobtitle_count.txt
chmod 666 /tmp/orangehrm_initial_jobtitle_count.txt 2>/dev/null || true

# Navigate to Admin > Job Titles
TARGET_URL="${ORANGEHRM_URL}/web/index.php/admin/viewJobTitleList"
ensure_orangehrm_logged_in "$TARGET_URL"

sleep 2
take_screenshot /tmp/task_start_state.png
log "Task start state screenshot saved"

echo "=== create_job_title task setup complete ==="
echo "Target: Create job title 'Cloud Architect'"
