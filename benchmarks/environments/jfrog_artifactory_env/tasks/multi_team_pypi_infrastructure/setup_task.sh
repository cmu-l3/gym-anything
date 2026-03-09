#!/bin/bash
# setup_task.sh — multi_team_pypi_infrastructure
# Removes all 8 target entities so the agent starts from a clean state.
set -e

source /workspace/scripts/task_utils.sh
chmod +x /workspace/tasks/multi_team_pypi_infrastructure/export_result.sh 2>/dev/null || true

echo "=== multi_team_pypi_infrastructure: Preparing environment ==="

# Wait for Artifactory to be ready
wait_for_artifactory 120

# --- Idempotent cleanup: delete in dependency order ---
# Virtual first (references local + remote repos)
delete_repo_if_exists "pypi-all"
delete_repo_if_exists "pypi-datascience"
delete_repo_if_exists "pypi-mlops"
delete_repo_if_exists "pypi-org-proxy"
# Permissions reference both repos and groups
delete_permission_if_exists "ds-pypi-perms"
delete_permission_if_exists "mlops-pypi-perms"
delete_group_if_exists "data-scientists"
delete_group_if_exists "mlops-engineers"

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
take_screenshot "/tmp/multi_team_pypi_infrastructure_start.png"

echo "=== multi_team_pypi_infrastructure: Setup complete ==="
exit 0
