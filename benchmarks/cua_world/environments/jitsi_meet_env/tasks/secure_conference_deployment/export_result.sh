#!/bin/bash

echo "=== Exporting secure_conference_deployment results ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
RESULT_FILE="/tmp/task_result.json"

# ── 1. Take final screenshot ────────────────────────────────────────────────
take_screenshot /tmp/task_final_screenshot.png

# ── 2. Check .env file ──────────────────────────────────────────────────────
ENV_FILE="/home/ga/jitsi/.env"
ENABLE_AUTH_SET="false"
AUTH_TYPE_SET="false"
ENABLE_GUESTS_SET="false"
ENV_MODIFIED="false"

if [ -f "$ENV_FILE" ]; then
    ENV_MTIME=$(stat -c %Y "$ENV_FILE" 2>/dev/null || echo "0")
    if [ "$ENV_MTIME" -gt "$TASK_START" ]; then ENV_MODIFIED="true"; fi
    grep -qE "^ENABLE_AUTH=1" "$ENV_FILE" 2>/dev/null && ENABLE_AUTH_SET="true"
    grep -qE "^AUTH_TYPE=internal" "$ENV_FILE" 2>/dev/null && AUTH_TYPE_SET="true"
    grep -qE "^ENABLE_GUESTS=1" "$ENV_FILE" 2>/dev/null && ENABLE_GUESTS_SET="true"
fi

# ── 3. Check custom-interface_config.js ──────────────────────────────────────
INTERFACE_CONFIG="/home/ga/.jitsi-meet-cfg/web/custom-interface_config.js"
BRANDING_CONFIGURED="false"
TOOLBAR_CONFIGURED="false"
MOBILE_PROMO_DISABLED="false"
INTERFACE_CONFIG_SIZE=0

if [ -f "$INTERFACE_CONFIG" ]; then
    INTERFACE_CONFIG_SIZE=$(stat -c%s "$INTERFACE_CONFIG" 2>/dev/null || echo "0")
    grep -qi "SecureConf" "$INTERFACE_CONFIG" 2>/dev/null && BRANDING_CONFIGURED="true"
    grep -qi "TOOLBAR_BUTTONS" "$INTERFACE_CONFIG" 2>/dev/null && TOOLBAR_CONFIGURED="true"
    grep -qi "MOBILE_APP_PROMO" "$INTERFACE_CONFIG" 2>/dev/null && MOBILE_PROMO_DISABLED="true"
    # Copy for verifier access
    cp "$INTERFACE_CONFIG" /tmp/custom-interface_config.js 2>/dev/null || true
    chmod 666 /tmp/custom-interface_config.js 2>/dev/null || true
fi

# ── 4. Check Docker container status ─────────────────────────────────────────
cd /home/ga/jitsi
ALL_CONTAINERS_RUNNING="false"
CONTAINERS_RESTARTED="false"

PROSODY_ID=$(docker compose ps -q prosody 2>/dev/null || echo "")
JICOFO_ID=$(docker compose ps -q jicofo 2>/dev/null || echo "")
JVB_ID=$(docker compose ps -q jvb 2>/dev/null || echo "")
WEB_ID=$(docker compose ps -q web 2>/dev/null || echo "")

if [ -n "$PROSODY_ID" ] && [ -n "$JICOFO_ID" ] && [ -n "$JVB_ID" ] && [ -n "$WEB_ID" ]; then
    RUNNING_COUNT=$(docker inspect -f '{{.State.Running}}' \
        "$PROSODY_ID" "$JICOFO_ID" "$JVB_ID" "$WEB_ID" 2>/dev/null | grep -c "true")
    if [ "$RUNNING_COUNT" -eq 4 ]; then ALL_CONTAINERS_RUNNING="true"; fi

    # Check if prosody was restarted after task started
    START_TS=$(docker inspect -f '{{.State.StartedAt}}' "$PROSODY_ID" 2>/dev/null || echo "")
    START_EPOCH=$(date -d "$START_TS" +%s 2>/dev/null || echo "0")
    if [ "$START_EPOCH" -gt "$TASK_START" ]; then CONTAINERS_RESTARTED="true"; fi
fi

# ── 5. Check admin user in prosody ───────────────────────────────────────────
ADMIN_USER_EXISTS="false"
if [ -n "$PROSODY_ID" ]; then
    # User data stored at /config/data/<encoded_domain>/accounts/<user>.dat
    if docker exec "$PROSODY_ID" sh -c \
        "ls /config/data/meet%2ejitsi/accounts/admin.dat" >/dev/null 2>&1; then
        ADMIN_USER_EXISTS="true"
    fi
fi

# ── 6. Check report file ────────────────────────────────────────────────────
REPORT_FILE="/home/ga/secure_conference_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_CONTENT_B64=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_CONTENT_B64=$(base64 -w0 "$REPORT_FILE" 2>/dev/null || echo "")
fi

# ── 7. Check browser status ─────────────────────────────────────────────────
FIREFOX_RUNNING=$(pgrep -f firefox >/dev/null 2>&1 && echo "true" || echo "false")
EPIPHANY_RUNNING=$(pgrep -f epiphany >/dev/null 2>&1 && echo "true" || echo "false")

# ── 8. Check Jitsi web service health ────────────────────────────────────────
SERVICE_HEALTHY="false"
if curl -sfk "http://localhost:8080" >/dev/null 2>&1; then
    SERVICE_HEALTHY="true"
fi

# ── 9. Write result JSON ────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "env_modified": $ENV_MODIFIED,
    "enable_auth_set": $ENABLE_AUTH_SET,
    "auth_type_set": $AUTH_TYPE_SET,
    "enable_guests_set": $ENABLE_GUESTS_SET,
    "branding_configured": $BRANDING_CONFIGURED,
    "toolbar_configured": $TOOLBAR_CONFIGURED,
    "mobile_promo_disabled": $MOBILE_PROMO_DISABLED,
    "interface_config_size": $INTERFACE_CONFIG_SIZE,
    "all_containers_running": $ALL_CONTAINERS_RUNNING,
    "containers_restarted": $CONTAINERS_RESTARTED,
    "admin_user_exists": $ADMIN_USER_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "report_content_b64": "$REPORT_CONTENT_B64",
    "firefox_running": $FIREFOX_RUNNING,
    "epiphany_running": $EPIPHANY_RUNNING,
    "service_healthy": $SERVICE_HEALTHY,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
ENDJSON

rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="
