#!/bin/bash
echo "=== Exporting Docker Compose Profiles Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/projects/acme-stack"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

take_screenshot /tmp/task_final.png

# 1. Capture the Configuration Structure using `docker compose config`
# This parses the YAML for us and outputs JSON, which is much safer to verify than grep
echo "Extracting Compose configuration..."
cd "$PROJECT_DIR"
COMPOSE_CONFIG_JSON=$(docker compose config --format json 2>/dev/null || echo "{}")

# 2. Runtime Verification: Default Profile
echo "Testing default 'up' behavior..."
docker compose down 2>/dev/null || true
docker compose up -d 2>/dev/null
DEFAULT_RUNNING_COUNT=$(docker compose ps --format json 2>/dev/null | grep -c '"State": "running"')
DEFAULT_SERVICE_NAMES=$(docker compose ps --format '{{.Service}}' | tr '\n' ',' | sed 's/,$//')

# 3. Runtime Verification: GUI Profile
echo "Testing 'gui' profile behavior..."
docker compose down 2>/dev/null || true
docker compose --profile gui up -d 2>/dev/null
GUI_RUNNING_COUNT=$(docker compose --profile gui ps --format json 2>/dev/null | grep -c '"State": "running"')
GUI_SERVICE_NAMES=$(docker compose --profile gui ps --format '{{.Service}}' | tr '\n' ',' | sed 's/,$//')

# 4. Clean up
docker compose down 2>/dev/null || true

# 5. Check if file was modified
FILE_MTIME=$(stat -c %Y "$PROJECT_DIR/docker-compose.yml" 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "compose_config": $COMPOSE_CONFIG_JSON,
    "runtime_checks": {
        "default_running_count": $DEFAULT_RUNNING_COUNT,
        "default_services": "$DEFAULT_SERVICE_NAMES",
        "gui_running_count": $GUI_RUNNING_COUNT,
        "gui_services": "$GUI_SERVICE_NAMES"
    }
}
EOF

# Move result to safe location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="