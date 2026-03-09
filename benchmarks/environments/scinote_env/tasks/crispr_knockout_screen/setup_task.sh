#!/bin/bash
echo "=== Setting up crispr_knockout_screen task ==="

# Clean up previous task files
rm -f /tmp/crispr_knockout_screen_result.json 2>/dev/null || true
rm -f /tmp/crispr_initial_counts.json 2>/dev/null || true

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record baseline counts (agent starts from blank state)
INITIAL_PROJECT_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM projects;" | tr -d '[:space:]')
INITIAL_EXP_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM experiments;" | tr -d '[:space:]')
INITIAL_TASK_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM my_modules;" | tr -d '[:space:]')
INITIAL_REPO_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repositories;" | tr -d '[:space:]')

safe_write_json "/tmp/crispr_initial_counts.json" "{\"projects\": ${INITIAL_PROJECT_COUNT:-0}, \"experiments\": ${INITIAL_EXP_COUNT:-0}, \"tasks\": ${INITIAL_TASK_COUNT:-0}, \"repositories\": ${INITIAL_REPO_COUNT:-0}}"

echo "Baseline: projects=${INITIAL_PROJECT_COUNT}, experiments=${INITIAL_EXP_COUNT}, tasks=${INITIAL_TASK_COUNT}, repos=${INITIAL_REPO_COUNT}"

# Ensure Firefox is running at the SciNote login page
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

sleep 3
take_screenshot /tmp/crispr_knockout_screen_start_screenshot.png

echo "=== Setup complete. Agent must create full CRISPR screen documentation from scratch. ==="
