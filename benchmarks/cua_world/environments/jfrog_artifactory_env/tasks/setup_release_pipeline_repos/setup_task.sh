#!/bin/bash
# setup_task.sh — setup_release_pipeline_repos
# Clears all 5 target entities so the agent starts from a clean state.
set -e

source /workspace/scripts/task_utils.sh
chmod +x /workspace/tasks/setup_release_pipeline_repos/export_result.sh 2>/dev/null || true

echo "=== setup_release_pipeline_repos: Preparing environment ==="

# Wait for Artifactory to be ready (up to 120s)
wait_for_artifactory 120

# --- Idempotent cleanup: delete target entities if they already exist ---
# Delete virtual first because it references local+remote repos
delete_repo_if_exists "ms-build-virtual"
delete_repo_if_exists "ms-releases"
delete_repo_if_exists "maven-central-proxy"
delete_permission_if_exists "build-access"
delete_group_if_exists "build-engineers"

# --- Record baselines for do-nothing verification ---
REPO_COUNT=$(get_repo_count)
echo "$REPO_COUNT" > /tmp/initial_repo_count
echo "Initial repo count: $REPO_COUNT"

# Record task start timestamp
echo "$(date +%s)" > /tmp/task_start_ts

# --- Navigate Firefox to the Repositories page as the agent's starting view ---
ensure_firefox_running
sleep 2
navigate_to "http://localhost:8082/ui/admin/repositories"
sleep 3
take_screenshot "/tmp/setup_release_pipeline_repos_start.png"

echo "=== setup_release_pipeline_repos: Setup complete ==="
exit 0
