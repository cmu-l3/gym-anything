#!/bin/bash
# Setup for: create_access_token task
echo "=== Setting up create_access_token task ==="

source /workspace/scripts/task_utils.sh

echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Revoke any existing 'CI/CD pipeline token' to ensure clean state.
# Uses a Python helper to find and delete matching tokens one at a time.
echo "Cleaning up any existing 'CI/CD pipeline token' access tokens..."
TOKENS_JSON=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/access/api/v1/tokens" 2>/dev/null)

CICD_TOKEN_IDS=$(echo "$TOKENS_JSON" | python3 - << 'PYEOF'
import sys, json
try:
    data = json.loads(sys.stdin.read())
    tokens = data.get('tokens', [])
    for t in tokens:
        if 'CI/CD' in t.get('description', ''):
            print(t['token_id'])
except Exception as e:
    pass
PYEOF
)

if [ -n "$CICD_TOKEN_IDS" ]; then
    echo "$CICD_TOKEN_IDS" | while IFS= read -r TID; do
        if [ -n "$TID" ]; then
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
                -u "${ADMIN_USER}:${ADMIN_PASS}" \
                -X DELETE \
                "${ARTIFACTORY_URL}/access/api/v1/tokens/${TID}" 2>/dev/null)
            echo "  Revoked CI/CD token $TID (HTTP $STATUS)"
        fi
    done
    echo "CI/CD token cleanup complete"
else
    echo "No existing CI/CD pipeline tokens found (clean state)"
fi

ensure_firefox_running "http://localhost:8082"
sleep 2
# Navigate to Administration > Security > Access Tokens
navigate_to "http://localhost:8082/ui/admin/security/access-tokens"
sleep 4

take_screenshot /tmp/task_create_access_token_initial.png

echo ""
echo "=== create_access_token Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in: admin / password at http://localhost:8082 (if not already logged in)"
echo "  2. Navigate to Administration > Security > Access Tokens"
echo "  3. Click 'Generate Token'"
echo "  4. Description: CI/CD pipeline token  (EXACT text required)"
echo "  5. Expiration: set to 'Never expire' or 1 year"
echo "  6. Click 'Generate'"
echo "  7. Copy/note the displayed token (shown only once)"
echo ""
