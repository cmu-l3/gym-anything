#!/bin/bash
echo "=== Setting up create_protocol_template task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean up previous task files
rm -f /tmp/create_protocol_result.json 2>/dev/null || true
rm -f /tmp/initial_repo_proto_count 2>/dev/null || true

# Ensure clean state: delete any existing protocol with this name to prevent gaming
echo "Cleaning up any existing protocols with the target name..."
scinote_db_query "DELETE FROM protocols WHERE LOWER(TRIM(name)) = 'western blot protocol';" 2>/dev/null || true

# Record initial repository protocol count (my_module_id IS NULL means it's a template in the repo)
INITIAL_REPO_PROTO_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM protocols WHERE my_module_id IS NULL;" | tr -d '[:space:]')
echo "${INITIAL_REPO_PROTO_COUNT:-0}" > /tmp/initial_repo_proto_count
echo "Initial repository protocol count: ${INITIAL_REPO_PROTO_COUNT:-0}"

# Ensure Firefox is running and logged in
ensure_firefox_running "${SCINOTE_URL}/users/sign_in"

# Wait for page to load
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Task: Create 'Western Blot Protocol' in the protocol repository."