#!/bin/bash
# setup_task.sh — federated_npm_registry_setup
# Removes all 7 target entities so the agent starts from a clean state.
set -e

source /workspace/scripts/task_utils.sh
chmod +x /workspace/tasks/federated_npm_registry_setup/export_result.sh 2>/dev/null || true

echo "=== federated_npm_registry_setup: Preparing environment ==="

# Wait for Artifactory to be ready
wait_for_artifactory 120

# --- Idempotent cleanup: delete target entities in dependency order ---
# Virtual repo first (references local + remote)
delete_repo_if_exists "npm-all"
delete_repo_if_exists "npm-internal"
delete_repo_if_exists "npmjs-mirror"
delete_permission_if_exists "frontend-npm-perms"
delete_user_if_exists "frontend-lead"
delete_group_if_exists "frontend-developers"

# --- Record baselines ---
echo "$(date +%s)" > /tmp/task_start_ts
REPO_COUNT=$(get_repo_count)
echo "$REPO_COUNT" > /tmp/initial_repo_count
echo "Initial repo count: $REPO_COUNT"

# --- Navigate Firefox to the Repositories admin page ---
ensure_firefox_running
sleep 2
navigate_to "http://localhost:8082/ui/admin/repositories"
sleep 3
take_screenshot "/tmp/federated_npm_registry_setup_start.png"

echo "=== federated_npm_registry_setup: Setup complete ==="
exit 0
