#!/bin/bash
# Export script for multi_tenant_team_onboarding task

echo "=== Exporting multi_tenant_team_onboarding result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get admin token for API queries
TOKEN=$(get_rancher_token)
if [ -z "$TOKEN" ]; then
    echo "ERROR: Could not get admin token for verification."
    # Export empty state so verifier handles it gracefully
    cat > /tmp/multi_tenant_team_onboarding_result.json <<EOF
{"error": "Failed to authenticate to Rancher API as admin"}
EOF
    exit 1
fi

# Function to test user auth
test_user_auth() {
    local username=$1
    local password=$2
    local resp=$(curl -sk "https://localhost/v3-public/localProviders/local?action=login" \
        -H 'Content-Type: application/json' \
        -d "{\"username\":\"$username\",\"password\":\"$password\",\"responseType\":\"token\"}")
    local token=$(echo "$resp" | jq -r '.token // empty')
    if [ -n "$token" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# ── 1. Check user authentication ──────────────────────────────────────────────
echo "Testing user credentials..."
ALICE_AUTH=$(test_user_auth "alice-chen" "AlphaLead2024!")
BOB_AUTH=$(test_user_auth "bob-kumar" "AlphaDev2024!!")
CAROL_AUTH=$(test_user_auth "carol-santos" "BetaLead2024!")
DAVE_AUTH=$(test_user_auth "dave-oconnor" "BetaDev2024!!")

# ── 2. Export Users ──────────────────────────────────────────────────────────
echo "Exporting users..."
USERS_JSON=$(curl -sk "https://localhost/v3/users" -H "Authorization: Bearer $TOKEN" | \
    jq -c '[.data[] | {username: .username, principalIds: .principalIds, id: .id}]')
[ -z "$USERS_JSON" ] && USERS_JSON="[]"

# ── 3. Export Projects in local cluster ───────────────────────────────────────
echo "Exporting projects..."
PROJECTS_JSON=$(curl -sk "https://localhost/v3/projects?clusterId=local" -H "Authorization: Bearer $TOKEN" | \
    jq -c '[.data[] | {name: .name, id: .id, created: .created}]')
[ -z "$PROJECTS_JSON" ] && PROJECTS_JSON="[]"

# ── 4. Export Role Bindings ───────────────────────────────────────────────────
echo "Exporting role bindings..."
BINDINGS_JSON=$(curl -sk "https://localhost/v3/projectRoleTemplateBindings" -H "Authorization: Bearer $TOKEN" | \
    jq -c '[.data[] | {projectId: .projectId, userPrincipalId: .userPrincipalId, roleTemplateId: .roleTemplateId}]')
[ -z "$BINDINGS_JSON" ] && BINDINGS_JSON="[]"

# ── 5. Export Namespace Project Annotations ───────────────────────────────────
echo "Exporting namespace states..."
STAGING_PROJ=$(docker exec rancher kubectl get namespace staging -o jsonpath='{.metadata.annotations.field\.cattle\.io/projectId}' 2>/dev/null || echo "none")
FRONTEND_PROJ=$(docker exec rancher kubectl get namespace frontend-staging -o jsonpath='{.metadata.annotations.field\.cattle\.io/projectId}' 2>/dev/null || echo "none")

# Compile JSON Result securely using temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "auth_status": {
        "alice-chen": $ALICE_AUTH,
        "bob-kumar": $BOB_AUTH,
        "carol-santos": $CAROL_AUTH,
        "dave-oconnor": $DAVE_AUTH
    },
    "users": $USERS_JSON,
    "projects": $PROJECTS_JSON,
    "role_bindings": $BINDINGS_JSON,
    "namespaces": {
        "staging": "$STAGING_PROJ",
        "frontend-staging": "$FRONTEND_PROJ"
    }
}
EOF

# Move to final destination
rm -f /tmp/multi_tenant_team_onboarding_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/multi_tenant_team_onboarding_result.json
chmod 666 /tmp/multi_tenant_team_onboarding_result.json

echo "Result JSON written to /tmp/multi_tenant_team_onboarding_result.json"
echo "=== Export Complete ==="