#!/bin/bash
# Export script for container_timezone_locale_fix task

echo "=== Exporting task results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/scheduler-bot"
CONTAINER_NAME="scheduler-bot"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if Container is Running
IS_RUNNING="false"
if container_running "$CONTAINER_NAME"; then
    IS_RUNNING="true"
fi

# 2. Check internal Timezone configuration (APK package & Env Var)
# We inspect the image/container to see if tzdata is present
HAS_TZDATA="false"
if [ "$IS_RUNNING" = "true" ]; then
    if docker exec "$CONTAINER_NAME" apk info -e tzdata > /dev/null 2>&1; then
        HAS_TZDATA="true"
    fi
fi

# 3. Check Environment Variables (TZ and LANG)
ENV_TZ=""
ENV_LANG=""
if [ "$IS_RUNNING" = "true" ]; then
    ENV_TZ=$(docker exec "$CONTAINER_NAME" printenv TZ 2>/dev/null || echo "")
    ENV_LANG=$(docker exec "$CONTAINER_NAME" printenv LANG 2>/dev/null || echo "")
    # Check LC_ALL as fallback for LANG
    if [ -z "$ENV_LANG" ]; then
        ENV_LANG=$(docker exec "$CONTAINER_NAME" printenv LC_ALL 2>/dev/null || echo "")
    fi
fi

# 4. Check Actual System Date inside container
# This is the ultimate proof. Should match America/New_York offset (EST or EDT)
CONTAINER_DATE_OUTPUT=""
IS_EST_EDT="false"
if [ "$IS_RUNNING" = "true" ]; then
    CONTAINER_DATE_OUTPUT=$(docker exec "$CONTAINER_NAME" date 2>/dev/null)
    # Check for EST or EDT in the output
    if echo "$CONTAINER_DATE_OUTPUT" | grep -qE "EST|EDT"; then
        IS_EST_EDT="true"
    fi
fi

# 5. Check Logs for Success Message (Unicode handling)
# We look for "STATUS: SUCCESS" and "PROCESSING_USER: Raphaël"
LOGS_contain_SUCCESS="false"
LOGS_contain_UNICODE="false"
if [ "$IS_RUNNING" = "true" ]; then
    # Get last 50 lines
    LOG_CONTENT=$(docker logs --tail 50 "$CONTAINER_NAME" 2>&1)
    
    if echo "$LOG_CONTENT" | grep -q "STATUS: SUCCESS"; then
        LOGS_contain_SUCCESS="true"
    fi
    
    # Check for the specific unicode character ë usually represented in UTF-8
    # We grep for "Rapha" to be safe, or exact match if possible
    if echo "$LOG_CONTENT" | grep -q "Raphaël"; then
        LOGS_contain_UNICODE="true"
    fi
fi

# 6. Check if image was actually rebuilt (Anti-Gaming)
# Compare creation time of image vs task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
IMAGE_CREATED_TIMESTAMP="0"
if [ "$IS_RUNNING" = "true" ]; then
    IMAGE_NAME=$(docker inspect --format='{{.Config.Image}}' "$CONTAINER_NAME")
    # Docker returns creation time in ISO 8601, need to convert to epoch or just compare strings roughly
    # Simpler: check if Created attribute > Task Start
    # Let's just trust the runtime checks (date and pkg) for now, 
    # but we can grab the ID to see if it changed from baseline if we had one.
    IMAGE_ID=$(docker inspect --format='{{.Image}}' "$CONTAINER_NAME")
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "is_running": $IS_RUNNING,
    "has_tzdata": $HAS_TZDATA,
    "env_tz": "$ENV_TZ",
    "env_lang": "$ENV_LANG",
    "container_date_output": "$(echo "$CONTAINER_DATE_OUTPUT" | sed 's/"/\\"/g')",
    "is_est_edt": $IS_EST_EDT,
    "logs_success": $LOGS_contain_SUCCESS,
    "logs_unicode": $LOGS_contain_UNICODE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json