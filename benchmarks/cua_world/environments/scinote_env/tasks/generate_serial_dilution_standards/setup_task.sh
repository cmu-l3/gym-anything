#!/bin/bash
echo "=== Setting up generate_serial_dilution_standards task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Clean up previous task files
rm -f /tmp/serial_dilution_result.json 2>/dev/null || true
rm -f /tmp/initial_repository_count 2>/dev/null || true
rm -f /tmp/initial_repository_row_count 2>/dev/null || true

# Record initial inventory (repository) count
INITIAL_REPO_COUNT=$(get_repository_count)
echo "${INITIAL_REPO_COUNT:-0}" > /tmp/initial_repository_count
echo "Initial repository count: ${INITIAL_REPO_COUNT:-0}"

# Record initial repository row count (total items across all inventories)
INITIAL_ROW_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows;" | tr -d '[:space:]')
echo "${INITIAL_ROW_COUNT:-0}" > /tmp/initial_repository_row_count
echo "Initial repository row count: ${INITIAL_ROW_COUNT:-0}"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is running at the sign-in page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

# Allow UI to stabilize
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Create inventory 'BCA Assay Standards' and add 5 BSA standard items."