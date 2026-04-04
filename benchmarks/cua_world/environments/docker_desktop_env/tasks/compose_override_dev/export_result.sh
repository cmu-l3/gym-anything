#!/bin/bash
echo "=== Exporting compose_override_dev results ==="

source /workspace/scripts/task_utils.sh

# Paths
PROJECT_DIR="/home/ga/Documents/docker-projects/webapp"
RESULT_FILE="/tmp/task_result.json"
BASE_COMPOSE="$PROJECT_DIR/docker-compose.yml"
OVERRIDE_COMPOSE="$PROJECT_DIR/docker-compose.override.yml"

# 1. File Existence & Integrity Checks
OVERRIDE_EXISTS="false"
BASE_MODIFIED="false"
VALID_YAML="false"

if [ -f "$OVERRIDE_COMPOSE" ]; then
    OVERRIDE_EXISTS="true"
    # Basic YAML validation
    if python3 -c "import yaml; yaml.safe_load(open('$OVERRIDE_COMPOSE'))" 2>/dev/null; then
        VALID_YAML="true"
    fi
fi

# Check if base file was modified
CURRENT_MD5=$(md5sum "$BASE_COMPOSE" 2>/dev/null | awk '{print $1}')
ORIGINAL_MD5=$(cat /tmp/base_compose_md5.txt 2>/dev/null)

if [ "$CURRENT_MD5" != "$ORIGINAL_MD5" ]; then
    BASE_MODIFIED="true"
fi

# 2. Container Inspection
# We inspect specific containers by name as defined in docker-compose.yml
API_CONTAINER="webapp-api"
DB_CONTAINER="webapp-db"
WEB_CONTAINER="webapp-web"

# Helper to inspect container field
inspect_container() {
    local container=$1
    local format=$2
    docker inspect "$container" --format "$format" 2>/dev/null || echo ""
}

# Check running status
API_RUNNING=$(container_running "$API_CONTAINER" && echo "true" || echo "false")
DB_RUNNING=$(container_running "$DB_CONTAINER" && echo "true" || echo "false")
WEB_RUNNING=$(container_running "$WEB_CONTAINER" && echo "true" || echo "false")

# Inspect API Container
API_ENV=""
API_MOUNTS=""
API_CMD=""
API_PORTS=""

if [ "$API_RUNNING" = "true" ]; then
    API_ENV=$(inspect_container "$API_CONTAINER" '{{json .Config.Env}}')
    API_MOUNTS=$(inspect_container "$API_CONTAINER" '{{json .Mounts}}')
    API_CMD=$(inspect_container "$API_CONTAINER" '{{json .Config.Cmd}}')
    API_PORTS=$(inspect_container "$API_CONTAINER" '{{json .NetworkSettings.Ports}}')
fi

# Inspect DB Container
DB_PORTS=""
if [ "$DB_RUNNING" = "true" ]; then
    DB_PORTS=$(inspect_container "$DB_CONTAINER" '{{json .NetworkSettings.Ports}}')
fi

# 3. Merged Configuration Check
# Run docker compose config to see the final merged structure
cd "$PROJECT_DIR"
MERGED_CONFIG_VALID="false"
MERGED_CONFIG_OUTPUT=""

if su - ga -c "docker compose config" > /tmp/merged_config.yaml 2>&1; then
    MERGED_CONFIG_VALID="true"
    # We won't dump the whole config to JSON, just validation status
    # The container inspection is the source of truth for runtime state
fi

# 4. Anti-gaming: Check override file timestamp
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OVERRIDE_MTIME=$(stat -c %Y "$OVERRIDE_COMPOSE" 2>/dev/null || echo "0")
CREATED_DURING_TASK="false"
if [ "$OVERRIDE_MTIME" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
# We construct the JSON carefully to avoid shell escaping issues with the inspected JSON blobs
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "override_exists": $OVERRIDE_EXISTS,
    "valid_yaml": $VALID_YAML,
    "base_modified": $BASE_MODIFIED,
    "file_created_during_task": $CREATED_DURING_TASK,
    "services_running": {
        "api": $API_RUNNING,
        "db": $DB_RUNNING,
        "web": $WEB_RUNNING
    },
    "api_config": {
        "env": ${API_ENV:-"[]"},
        "mounts": ${API_MOUNTS:-"[]"},
        "cmd": ${API_CMD:-"[]"},
        "ports": ${API_PORTS:-"{}"}
    },
    "db_config": {
        "ports": ${DB_PORTS:-"{}"}
    },
    "merged_config_valid": $MERGED_CONFIG_VALID,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to $RESULT_FILE"
echo "=== Export complete ==="