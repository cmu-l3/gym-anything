#!/bin/bash
# Export script for Analyst User Access task

echo "=== Exporting Analyst User Access Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TARGET_LOGIN="jamie.rodriguez"

# ── Read seeded site IDs ──────────────────────────────────────────────────
MAIN_STORE_ID=$(cat /tmp/analyst_main_store_id 2>/dev/null || echo "")
BLOG_ID=$(cat /tmp/analyst_blog_id 2>/dev/null || echo "")
MOBILE_APP_ID=$(cat /tmp/analyst_mobile_app_id 2>/dev/null || echo "")
CONFIDENTIAL_ID=$(cat /tmp/analyst_confidential_id 2>/dev/null || echo "")
echo "Site IDs: Main=$MAIN_STORE_ID Blog=$BLOG_ID MobileApp=$MOBILE_APP_ID Conf=$CONFIDENTIAL_ID"

INITIAL_USER_IDS=$(cat /tmp/initial_user_ids 2>/dev/null || echo "")

# ── Debug ─────────────────────────────────────────────────────────────────
echo ""
echo "=== DEBUG: Users ==="
matomo_query_verbose "SELECT login, email FROM matomo_user ORDER BY login" 2>/dev/null
echo ""
echo "=== DEBUG: Access for $TARGET_LOGIN ==="
matomo_query_verbose "SELECT login, idsite, access FROM matomo_access WHERE LOWER(login)=LOWER('$TARGET_LOGIN')" 2>/dev/null
echo ""
echo "=== DEBUG: Reports for $TARGET_LOGIN ==="
matomo_query_verbose "SELECT idreport, idsite, login, period, type, deleted FROM matomo_report WHERE LOWER(login)=LOWER('$TARGET_LOGIN')" 2>/dev/null
echo "=== END DEBUG ==="
echo ""

# ── Check user existence ──────────────────────────────────────────────────
USER_DATA=$(matomo_query "SELECT login, email FROM matomo_user WHERE LOWER(login)=LOWER('$TARGET_LOGIN') LIMIT 1" 2>/dev/null)
USER_EXISTS="false"
USER_EMAIL=""
if [ -n "$USER_DATA" ]; then
    USER_EXISTS="true"
    USER_EMAIL=$(echo "$USER_DATA" | cut -f2)
fi
echo "User $TARGET_LOGIN exists: $USER_EXISTS (email=$USER_EMAIL)"

# Check if user is newly created
USER_IS_NEW="false"
if [ "$USER_EXISTS" = "true" ]; then
    if [ -z "$INITIAL_USER_IDS" ] || ! echo ",$INITIAL_USER_IDS," | grep -qi ",$TARGET_LOGIN,"; then
        USER_IS_NEW="true"
    fi
fi
echo "User is new: $USER_IS_NEW"

# ── Check access permissions ──────────────────────────────────────────────
check_access() {
    local login="$1"
    local idsite="$2"
    matomo_query "SELECT access FROM matomo_access WHERE LOWER(login)=LOWER('$login') AND idsite=$idsite LIMIT 1" 2>/dev/null
}

ACCESS_MAIN="none"
ACCESS_BLOG="none"
ACCESS_MOBILE="none"
ACCESS_CONF="none"

if [ "$USER_EXISTS" = "true" ]; then
    [ -n "$MAIN_STORE_ID" ] && A=$(check_access "$TARGET_LOGIN" "$MAIN_STORE_ID") && [ -n "$A" ] && ACCESS_MAIN="$A"
    [ -n "$BLOG_ID" ]       && A=$(check_access "$TARGET_LOGIN" "$BLOG_ID")       && [ -n "$A" ] && ACCESS_BLOG="$A"
    [ -n "$MOBILE_APP_ID" ] && A=$(check_access "$TARGET_LOGIN" "$MOBILE_APP_ID") && [ -n "$A" ] && ACCESS_MOBILE="$A"
    [ -n "$CONFIDENTIAL_ID" ] && A=$(check_access "$TARGET_LOGIN" "$CONFIDENTIAL_ID") && [ -n "$A" ] && ACCESS_CONF="$A"
fi

echo "Access: MainStore=$ACCESS_MAIN Blog=$ACCESS_BLOG MobileApp=$ACCESS_MOBILE Confidential=$ACCESS_CONF"

# ── Check monthly report ──────────────────────────────────────────────────
REPORT_DATA=""
REPORT_EXISTS="false"
REPORT_PERIOD=""
REPORT_SITE_ID=""

if [ "$USER_EXISTS" = "true" ] && [ -n "$MAIN_STORE_ID" ]; then
    REPORT_DATA=$(matomo_query "SELECT idreport, idsite, period FROM matomo_report WHERE LOWER(login)=LOWER('$TARGET_LOGIN') AND deleted=0 LIMIT 1" 2>/dev/null)
    if [ -n "$REPORT_DATA" ]; then
        REPORT_EXISTS="true"
        REPORT_SITE_ID=$(echo "$REPORT_DATA" | cut -f2)
        REPORT_PERIOD=$(echo "$REPORT_DATA" | cut -f3)
    fi
fi
echo "Report: exists=$REPORT_EXISTS period=$REPORT_PERIOD site=$REPORT_SITE_ID (expected=$MAIN_STORE_ID)"

# ── Write JSON ────────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/analyst_user_access_result.XXXXXX.json)
cat > "$TEMP_JSON" << JSONEOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "target_login": "$TARGET_LOGIN",
    "user_exists": $USER_EXISTS,
    "user_is_new": $USER_IS_NEW,
    "user_email": "$USER_EMAIL",
    "initial_user_ids": "$(echo "$INITIAL_USER_IDS" | sed 's/"/\\"/g')",
    "site_ids": {
        "main_store": "${MAIN_STORE_ID}",
        "blog": "${BLOG_ID}",
        "mobile_app": "${MOBILE_APP_ID}",
        "confidential": "${CONFIDENTIAL_ID}"
    },
    "access": {
        "main_store": "$ACCESS_MAIN",
        "blog": "$ACCESS_BLOG",
        "mobile_app": "$ACCESS_MOBILE",
        "confidential": "$ACCESS_CONF"
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "period": "$REPORT_PERIOD",
        "idsite": "$REPORT_SITE_ID"
    },
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

rm -f /tmp/analyst_user_access_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/analyst_user_access_result.json
chmod 666 /tmp/analyst_user_access_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/analyst_user_access_result.json"
cat /tmp/analyst_user_access_result.json

echo ""
echo "=== Export Complete ==="
