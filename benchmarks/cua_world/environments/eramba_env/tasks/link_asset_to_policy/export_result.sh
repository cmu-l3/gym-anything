#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting task results: link_asset_to_policy ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Retrieve IDs saved during setup
POLICY_ID=$(cat /tmp/target_policy_id.txt 2>/dev/null || echo "")
ASSET_ID=$(cat /tmp/target_asset_id.txt 2>/dev/null || echo "")

echo "  Checking Policy ID: $POLICY_ID"
echo "  Checking Asset ID: $ASSET_ID"

# ---------------------------------------------------------------
# 1. Verify Entities Still Exist
# ---------------------------------------------------------------
POLICY_EXISTS="false"
if [ -n "$POLICY_ID" ]; then
    CNT=$(eramba_db_query "SELECT COUNT(*) FROM security_policies WHERE id=${POLICY_ID} AND deleted=0;" 2>/dev/null || echo "0")
    if [ "$CNT" = "1" ]; then POLICY_EXISTS="true"; fi
fi

ASSET_EXISTS="false"
if [ -n "$ASSET_ID" ]; then
    CNT=$(eramba_db_query "SELECT COUNT(*) FROM business_assets WHERE id=${ASSET_ID} AND deleted=0;" 2>/dev/null || echo "0")
    if [ "$CNT" = "1" ]; then ASSET_EXISTS="true"; fi
fi

# ---------------------------------------------------------------
# 2. Verify Association (The Core Task)
# ---------------------------------------------------------------
ASSOCIATION_FOUND="false"

if [ "$POLICY_EXISTS" = "true" ] && [ "$ASSET_EXISTS" = "true" ]; then
    # Check likely join table names (Eramba uses CakePHP conventions)
    # 1. business_assets_security_policies
    COUNT_A=$(eramba_db_query "SELECT COUNT(*) FROM business_assets_security_policies WHERE security_policy_id=${POLICY_ID} AND business_asset_id=${ASSET_ID};" 2>/dev/null || echo "0")
    
    # 2. security_policies_business_assets (reverse order check)
    COUNT_B=$(eramba_db_query "SELECT COUNT(*) FROM security_policies_business_assets WHERE security_policy_id=${POLICY_ID} AND business_asset_id=${ASSET_ID};" 2>/dev/null || echo "0")

    if [ "$COUNT_A" -gt "0" ] || [ "$COUNT_B" -gt "0" ]; then
        ASSOCIATION_FOUND="true"
    fi
fi

# ---------------------------------------------------------------
# 3. Verify Timestamp (Anti-gaming)
# ---------------------------------------------------------------
POLICY_MODIFIED="false"
if [ "$POLICY_EXISTS" = "true" ]; then
    # Get modification timestamp (UNIX)
    MOD_TS=$(eramba_db_query "SELECT UNIX_TIMESTAMP(modified) FROM security_policies WHERE id=${POLICY_ID};" 2>/dev/null || echo "0")
    
    # Check if modified after task start
    if [ "$MOD_TS" -gt "$TASK_START" ]; then
        POLICY_MODIFIED="true"
    fi
fi

# ---------------------------------------------------------------
# 4. Final Screenshot & Export
# ---------------------------------------------------------------
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then SCREENSHOT_EXISTS="true"; fi

# Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "policy_exists": $POLICY_EXISTS,
    "asset_exists": $ASSET_EXISTS,
    "association_found": $ASSOCIATION_FOUND,
    "policy_modified_during_task": $POLICY_MODIFIED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with safe permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json