#!/bin/bash
# Post-task export for deactivate_leaver_accounts
# Checks the existence of users via API and captures final state.

echo "=== Exporting Deactivate Leaver Accounts Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check User Status via REST API
# We need to check 4 users:
# - mholloway (Should be GONE)
# - clille (Should be GONE)
# - sdhawan (Should EXIST)
# - Administrator (Should EXIST - sanity check)

check_user_status() {
    local username="$1"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/user/$username")
    
    if [ "$code" = "200" ]; then
        echo "true"
    else
        echo "false"
    fi
}

MH_EXISTS=$(check_user_status "mholloway")
CL_EXISTS=$(check_user_status "clille")
SD_EXISTS=$(check_user_status "sdhawan")
ADMIN_EXISTS=$(check_user_status "Administrator")

# 3. Get Task Timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "users": {
        "mholloway_exists": $MH_EXISTS,
        "clille_exists": $CL_EXISTS,
        "sdhawan_exists": $SD_EXISTS,
        "administrator_exists": $ADMIN_EXISTS
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with read permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="