#!/bin/bash
echo "=== Setting up create_inventory_item task ==="

# Clean up previous task files
rm -f /tmp/create_inventory_result.json 2>/dev/null || true
rm -f /tmp/initial_repository_count 2>/dev/null || true
rm -f /tmp/initial_repository_row_count 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial inventory (repository) count
INITIAL_REPO_COUNT=$(get_repository_count)
echo "${INITIAL_REPO_COUNT:-0}" > /tmp/initial_repository_count
echo "Initial repository count: ${INITIAL_REPO_COUNT:-0}"

# Record initial repository row count (total across all)
INITIAL_ROW_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows;" | tr -d '[:space:]')
echo "${INITIAL_ROW_COUNT:-0}" > /tmp/initial_repository_row_count
echo "Initial repository row count: ${INITIAL_ROW_COUNT:-0}"

# Ensure Firefox is running at the login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Create inventory 'Lab Reagents' and add item 'Tris-HCl Buffer pH 7.4'"
