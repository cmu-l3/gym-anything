#!/bin/bash
# Export script for docker_legacy_network_shim
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_final.png

PROJECT_DIR="/home/ga/projects/fincore-migration"
cd "$PROJECT_DIR" || exit 1

# 1. Code Integrity Check
ORIGINAL_MD5=$(cat /tmp/main_py_checksum.txt 2>/dev/null || echo "original_missing")
CURRENT_MD5=$(md5sum "$PROJECT_DIR/app/main.py" 2>/dev/null | awk '{print $1}' || echo "current_missing")
CODE_MODIFIED="false"
if [ "$ORIGINAL_MD5" != "$CURRENT_MD5" ]; then
    CODE_MODIFIED="true"
fi

# 2. Inspect Containers
# We need to find the container IDs associated with the compose project
# Assuming standard compose naming: fincore-migration-service-1
DB_CONTAINER=$(docker compose ps -q db 2>/dev/null)
AUTH_CONTAINER=$(docker compose ps -q auth-mock 2>/dev/null)
APP_CONTAINER=$(docker compose ps -q fincore-app 2>/dev/null)

# 2a. Check Aliases
DB_ALIASES="[]"
if [ -n "$DB_CONTAINER" ]; then
    DB_ALIASES=$(docker inspect "$DB_CONTAINER" --format '{{json .NetworkSettings.Networks}}')
fi

AUTH_ALIASES="[]"
if [ -n "$AUTH_CONTAINER" ]; then
    AUTH_ALIASES=$(docker inspect "$AUTH_CONTAINER" --format '{{json .NetworkSettings.Networks}}')
fi

# 2b. Check Environment
APP_ENV="[]"
if [ -n "$APP_CONTAINER" ]; then
    APP_ENV=$(docker inspect "$APP_CONTAINER" --format '{{json .Config.Env}}')
fi

# 2c. Check Volume Mounts
APP_MOUNTS="[]"
if [ -n "$APP_CONTAINER" ]; then
    APP_MOUNTS=$(docker inspect "$APP_CONTAINER" --format '{{json .Mounts}}')
fi

# 2d. Check App Status
APP_RUNNING="false"
if [ -n "$APP_CONTAINER" ]; then
    STATUS=$(docker inspect "$APP_CONTAINER" --format '{{.State.Status}}')
    if [ "$STATUS" == "running" ]; then
        APP_RUNNING="true"
    fi
fi

# 3. Check Success Log on Host (Proof of Persistence)
LOG_FILE="$PROJECT_DIR/logs/startup_success.log"
LOG_EXISTS="false"
LOG_CONTENT=""

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    LOG_CONTENT=$(cat "$LOG_FILE")
fi

# 4. JSON Export
cat > /tmp/task_result.json << EOF
{
    "code_modified": $CODE_MODIFIED,
    "app_running": $APP_RUNNING,
    "db_aliases": $DB_ALIASES,
    "auth_aliases": $AUTH_ALIASES,
    "app_env": $APP_ENV,
    "app_mounts": $APP_MOUNTS,
    "log_exists_on_host": $LOG_EXISTS,
    "log_content": "$(echo "$LOG_CONTENT" | tr -d '\n' | sed 's/"/\\"/g')",
    "original_md5": "$ORIGINAL_MD5",
    "current_md5": "$CURRENT_MD5"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="