#!/bin/bash
echo "=== Setting up create_research_team task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any potential previous artifacts to ensure clean state
echo "Cleaning up any pre-existing colliding data..."
scinote_db_query "DELETE FROM projects WHERE name='AAV Vector Optimization Study';" >/dev/null 2>&1 || true
scinote_db_query "DELETE FROM teams WHERE name='CRISPR Gene Therapy Consortium';" >/dev/null 2>&1 || true

# Record initial counts
INITIAL_TEAM_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM teams;" | tr -d '[:space:]')
INITIAL_PROJECT_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM projects;" | tr -d '[:space:]')
DEFAULT_TEAM_ID=$(scinote_db_query "SELECT id FROM teams ORDER BY id ASC LIMIT 1;" | tr -d '[:space:]')

echo "${INITIAL_TEAM_COUNT:-0}" > /tmp/initial_team_count
echo "${INITIAL_PROJECT_COUNT:-0}" > /tmp/initial_project_count
echo "${DEFAULT_TEAM_ID:-1}" > /tmp/default_team_id

echo "Initial team count: ${INITIAL_TEAM_COUNT:-0}"
echo "Initial project count: ${INITIAL_PROJECT_COUNT:-0}"
echo "Default team ID: ${DEFAULT_TEAM_ID:-1}"

# Ensure Firefox is running and user is at the login/dashboard
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

# Let UI settle
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Create team 'CRISPR Gene Therapy Consortium' and project 'AAV Vector Optimization Study' within it."