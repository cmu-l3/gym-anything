#!/bin/bash
echo "=== Setting up task: create_structured_inventory ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure Docker and SciNote are healthy
ensure_docker_healthy
wait_for_scinote_ready 120

# Record initial counts to detect "do nothing"
INITIAL_REPO_COUNT=$(get_repository_count)
echo "${INITIAL_REPO_COUNT:-0}" > /tmp/initial_repo_count.txt

INITIAL_COL_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_columns;" | tr -d '[:space:]')
echo "${INITIAL_COL_COUNT:-0}" > /tmp/initial_col_count.txt

INITIAL_ROW_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows;" | tr -d '[:space:]')
echo "${INITIAL_ROW_COUNT:-0}" > /tmp/initial_row_count.txt

# Ensure Firefox is running and pointed at sign-in page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"
sleep 3

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="