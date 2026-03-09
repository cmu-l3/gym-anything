#!/bin/bash
# Export script for Debug Broken Pipelines task
# Checks the last build result for each of the 3 pipeline jobs.

echo "=== Exporting Debug Broken Pipelines Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Read initial build baselines
INIT_PAYMENT=$(cat /tmp/initial_build_payment_service_ci 2>/dev/null || echo "0")
INIT_AUTH=$(cat /tmp/initial_build_user_auth_service 2>/dev/null || echo "0")
INIT_INVENTORY=$(cat /tmp/initial_build_inventory_api_build 2>/dev/null || echo "0")

echo "Initial build baselines: payment=$INIT_PAYMENT, auth=$INIT_AUTH, inventory=$INIT_INVENTORY"

# ─────────────────────────────────────────────────────────────
# Query last build for each job
# ─────────────────────────────────────────────────────────────
get_build_info() {
    local job="$1"
    # Returns: RESULT NUMBER (tab-separated), or UNKNOWN 0
    local info
    info=$(jenkins_api "job/$job/lastBuild/api/json" 2>/dev/null)
    if [ -z "$info" ] || echo "$info" | grep -q '"404"'; then
        echo "NO_BUILD 0"
        return
    fi
    local result number
    result=$(echo "$info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result') or 'IN_PROGRESS')" 2>/dev/null || echo "UNKNOWN")
    number=$(echo "$info" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('number',0))" 2>/dev/null || echo "0")
    echo "$result $number"
}

# payment-service-ci
read -r PAYMENT_RESULT PAYMENT_BUILD_NUM <<< "$(get_build_info payment-service-ci)"
echo "payment-service-ci: result=$PAYMENT_RESULT, build=$PAYMENT_BUILD_NUM (baseline=$INIT_PAYMENT)"

# user-auth-service
read -r AUTH_RESULT AUTH_BUILD_NUM <<< "$(get_build_info user-auth-service)"
echo "user-auth-service: result=$AUTH_RESULT, build=$AUTH_BUILD_NUM (baseline=$INIT_AUTH)"

# inventory-api-build
read -r INVENTORY_RESULT INVENTORY_BUILD_NUM <<< "$(get_build_info inventory-api-build)"
echo "inventory-api-build: result=$INVENTORY_RESULT, build=$INVENTORY_BUILD_NUM (baseline=$INIT_INVENTORY)"

# ─────────────────────────────────────────────────────────────
# Check if new builds were triggered (build number > baseline)
# ─────────────────────────────────────────────────────────────
PAYMENT_NEW_BUILD=false
AUTH_NEW_BUILD=false
INVENTORY_NEW_BUILD=false

[ "$PAYMENT_BUILD_NUM" -gt "$INIT_PAYMENT" ] 2>/dev/null && PAYMENT_NEW_BUILD=true
[ "$AUTH_BUILD_NUM" -gt "$INIT_AUTH" ] 2>/dev/null && AUTH_NEW_BUILD=true
[ "$INVENTORY_BUILD_NUM" -gt "$INIT_INVENTORY" ] 2>/dev/null && INVENTORY_NEW_BUILD=true

echo "New builds: payment=$PAYMENT_NEW_BUILD, auth=$AUTH_NEW_BUILD, inventory=$INVENTORY_NEW_BUILD"

# ─────────────────────────────────────────────────────────────
# For job 2: also check if credential 'github-deploy-key' was created
# (alternative fix: agent creates the missing credential)
# ─────────────────────────────────────────────────────────────
CRED_DEPLOY_KEY_EXISTS=false
CREDS_JSON=$(jenkins_api "credentials/store/system/domain/_/api/json?depth=1" 2>/dev/null)
if [ -n "$CREDS_JSON" ]; then
    MATCH=$(echo "$CREDS_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ids = [c.get('id','') for c in d.get('credentials', [])]
    print('true' if 'github-deploy-key' in ids else 'false')
except:
    print('false')
" 2>/dev/null)
    CRED_DEPLOY_KEY_EXISTS="$MATCH"
fi
echo "Credential 'github-deploy-key' exists: $CRED_DEPLOY_KEY_EXISTS"

# ─────────────────────────────────────────────────────────────
# Write result JSON
# ─────────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/debug_broken_pipelines_result.XXXXXX.json)
jq -n \
    --arg payment_result "$PAYMENT_RESULT" \
    --argjson payment_build_num "${PAYMENT_BUILD_NUM:-0}" \
    --argjson payment_baseline "${INIT_PAYMENT:-0}" \
    --argjson payment_new_build "$PAYMENT_NEW_BUILD" \
    --arg auth_result "$AUTH_RESULT" \
    --argjson auth_build_num "${AUTH_BUILD_NUM:-0}" \
    --argjson auth_baseline "${INIT_AUTH:-0}" \
    --argjson auth_new_build "$AUTH_NEW_BUILD" \
    --argjson cred_deploy_key_exists "$CRED_DEPLOY_KEY_EXISTS" \
    --arg inventory_result "$INVENTORY_RESULT" \
    --argjson inventory_build_num "${INVENTORY_BUILD_NUM:-0}" \
    --argjson inventory_baseline "${INIT_INVENTORY:-0}" \
    --argjson inventory_new_build "$INVENTORY_NEW_BUILD" \
    --arg timestamp "$(date -Iseconds)" \
    '{
        payment_service_ci: {
            result: $payment_result,
            build_number: $payment_build_num,
            baseline_build_number: $payment_baseline,
            new_build_triggered: $payment_new_build
        },
        user_auth_service: {
            result: $auth_result,
            build_number: $auth_build_num,
            baseline_build_number: $auth_baseline,
            new_build_triggered: $auth_new_build,
            credential_github_deploy_key_created: $cred_deploy_key_exists
        },
        inventory_api_build: {
            result: $inventory_result,
            build_number: $inventory_build_num,
            baseline_build_number: $inventory_baseline,
            new_build_triggered: $inventory_new_build
        },
        export_timestamp: $timestamp
    }' > "$TEMP_JSON"

rm -f /tmp/debug_broken_pipelines_result.json 2>/dev/null || sudo rm -f /tmp/debug_broken_pipelines_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/debug_broken_pipelines_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/debug_broken_pipelines_result.json
chmod 666 /tmp/debug_broken_pipelines_result.json 2>/dev/null || sudo chmod 666 /tmp/debug_broken_pipelines_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON:"
cat /tmp/debug_broken_pipelines_result.json
echo ""
echo "=== Export Complete ==="
