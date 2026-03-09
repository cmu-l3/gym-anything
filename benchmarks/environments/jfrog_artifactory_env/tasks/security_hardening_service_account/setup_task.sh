#!/bin/bash
# setup_task.sh — security_hardening_service_account
# Removes all 5 target entities so the agent starts from a clean state.
set -e

source /workspace/scripts/task_utils.sh
chmod +x /workspace/tasks/security_hardening_service_account/export_result.sh 2>/dev/null || true

echo "=== security_hardening_service_account: Preparing environment ==="

# Wait for Artifactory to be ready
wait_for_artifactory 120

# --- Idempotent cleanup ---
# Delete permission before group/repo (references both)
delete_permission_if_exists "svc-deploy-perms"
delete_user_if_exists "svc-deploy"
delete_group_if_exists "ci-services"
delete_repo_if_exists "npm-builds"

# Revoke any existing access tokens matching the target description
TOKENS_JSON=$(curl -s -u "admin:password" "http://localhost:8082/access/api/v1/tokens" 2>/dev/null || echo "")
if [ -n "$TOKENS_JSON" ]; then
    echo "$TOKENS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for t in data.get('tokens', []):
        desc = t.get('description', '') or ''
        if 'Q1 2026 rotation' in desc:
            print(t.get('token_id', ''))
except Exception:
    pass
" 2>/dev/null | while IFS= read -r tid; do
        if [ -n "$tid" ]; then
            curl -s -u "admin:password" -X DELETE \
                "http://localhost:8082/access/api/v1/tokens/$tid" > /dev/null 2>&1 || true
            echo "Revoked token: $tid"
        fi
    done
fi

# --- Record baselines ---
echo "$(date +%s)" > /tmp/task_start_ts
REPO_COUNT=$(get_repo_count)
echo "$REPO_COUNT" > /tmp/initial_repo_count
echo "Initial repo count: $REPO_COUNT"

# --- Navigate Firefox to the Users admin page ---
ensure_firefox_running
sleep 2
navigate_to "http://localhost:8082/ui/admin/security/users"
sleep 3
take_screenshot "/tmp/security_hardening_service_account_start.png"

echo "=== security_hardening_service_account: Setup complete ==="
exit 0
