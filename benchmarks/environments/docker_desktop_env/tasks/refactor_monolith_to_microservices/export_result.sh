#!/bin/bash
echo "=== Exporting Refactor Monolith Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/legacy_project"
RESULT_FILE="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
COMPOSE_EXISTS="false"
COMPOSE_VALID="false"
SERVICE_COUNT=0
APP_RUNNING="false"
DB_RUNNING="false"
APP_ACCESSIBLE="false"
DB_IMAGE_CORRECT="false"
APP_IMAGE_CLEAN="false"
VOLUME_USED="false"
APP_RESPONSE=""

# 1. Check docker-compose.yml
if [ -f "$PROJECT_DIR/docker-compose.yml" ] || [ -f "$PROJECT_DIR/docker-compose.yaml" ]; then
    COMPOSE_EXISTS="true"
    # Basic validation
    if docker compose -f "$PROJECT_DIR/docker-compose.yml" config >/dev/null 2>&1; then
        COMPOSE_VALID="true"
    fi
fi

# 2. Inspect Running Services (via Docker Compose)
cd "$PROJECT_DIR"
# Get running services for this project
RUNNING_SERVICES=$(docker compose ps --services --filter "status=running" 2>/dev/null)
if [ -n "$RUNNING_SERVICES" ]; then
    SERVICE_COUNT=$(echo "$RUNNING_SERVICES" | wc -l)
    
    if echo "$RUNNING_SERVICES" | grep -q "app"; then APP_RUNNING="true"; fi
    if echo "$RUNNING_SERVICES" | grep -q "db"; then DB_RUNNING="true"; fi
fi

# 3. Check Database Image
if [ "$DB_RUNNING" = "true" ]; then
    # Get the image ID of the running db service
    DB_CONTAINER=$(docker compose ps -q db 2>/dev/null)
    if [ -n "$DB_CONTAINER" ]; then
        DB_IMAGE=$(docker inspect --format '{{.Config.Image}}' "$DB_CONTAINER")
        if [[ "$DB_IMAGE" == *"postgres"* ]]; then
            DB_IMAGE_CORRECT="true"
        fi
        
        # Check for volumes
        MOUNTS=$(docker inspect --format '{{json .Mounts}}' "$DB_CONTAINER")
        if echo "$MOUNTS" | grep -q '"Type":"volume"'; then
            VOLUME_USED="true"
        fi
    fi
fi

# 4. Check App Image (Cleanup verification)
if [ "$APP_RUNNING" = "true" ]; then
    APP_CONTAINER=$(docker compose ps -q app 2>/dev/null)
    if [ -n "$APP_CONTAINER" ]; then
        APP_IMAGE_ID=$(docker inspect --format '{{.Image}}' "$APP_CONTAINER")
        
        # Check history for "apt-get install postgresql"
        # If the user cleaned the Dockerfile, this command shouldn't be in the *recent* history 
        # of the built image (unless they based it off the dirty one, which is unlikely).
        # We check if the history contains the specific install command.
        HISTORY=$(docker history --no-trunc "$APP_IMAGE_ID" 2>/dev/null)
        
        if ! echo "$HISTORY" | grep -q "apt-get install -y postgresql"; then
            APP_IMAGE_CLEAN="true"
        fi
    fi
fi

# 5. Check Connectivity
# Try to access the app
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 http://localhost:5000 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    APP_ACCESSIBLE="true"
    APP_RESPONSE=$(curl -s http://localhost:5000)
fi

# Create JSON result
# Use a temp file to avoid race conditions/permissions
TEMP_JSON=$(mktemp /tmp/refactor_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "compose_exists": $COMPOSE_EXISTS,
    "compose_valid": $COMPOSE_VALID,
    "service_count": $SERVICE_COUNT,
    "app_running": $APP_RUNNING,
    "db_running": $DB_RUNNING,
    "app_accessible": $APP_ACCESSIBLE,
    "db_image_correct": $DB_IMAGE_CORRECT,
    "app_image_clean": $APP_IMAGE_CLEAN,
    "volume_used": $VOLUME_USED,
    "app_response": $(echo "$APP_RESPONSE" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()) if sys.stdin.read().strip() else "\"\"")'),
    "timestamp": $(date +%s)
}
EOF

# Move to final location
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="