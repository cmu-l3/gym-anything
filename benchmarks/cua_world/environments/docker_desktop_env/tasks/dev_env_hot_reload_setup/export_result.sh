#!/bin/bash
echo "=== Exporting Hot Reload Verification Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/projects/quote-service"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
APP_FILE="$PROJECT_DIR/src/app.py"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize results
APP_ACCESSIBLE="false"
HOT_RELOAD_SUCCESS="false"
CONTAINER_STABLE="false"
HAS_VOLUMES="false"
HAS_COMMAND_OVERRIDE="false"
HTTP_RESPONSE_1=""
HTTP_RESPONSE_2=""

# Check YAML content statically
if [ -f "$COMPOSE_FILE" ]; then
    if grep -q "volumes:" "$COMPOSE_FILE"; then
        HAS_VOLUMES="true"
    fi
    if grep -q "command:" "$COMPOSE_FILE"; then
        HAS_COMMAND_OVERRIDE="true"
    fi
fi

# Functional Verification Logic
# We perform the test inside the environment to verify hot reload behavior

# 1. Ensure the app is running (try to start if not)
cd "$PROJECT_DIR"
if ! docker compose ps --format '{{.State}}' | grep -q "running"; then
    echo "Container not running, attempting to start..."
    su - ga -c "docker compose up -d"
    sleep 5
fi

# 2. Get Container ID (to check stability)
CONTAINER_ID_START=$(docker compose ps -q web 2>/dev/null || docker ps -q --filter "ancestor=quote-service-web" | head -1)

# 3. Test 1: Check baseline response
echo "Checking baseline response..."
sleep 2
HTTP_RESPONSE_1=$(curl -s --max-time 2 http://localhost:5000 2>/dev/null || echo "ERROR")

if [[ "$HTTP_RESPONSE_1" == *"Quote Service"* ]]; then
    APP_ACCESSIBLE="true"
    
    # 4. Perform Hot Reload Test
    echo "Modifying source code..."
    # Backup original
    cp "$APP_FILE" "$APP_FILE.bak"
    
    # Modify the text in the app
    sed -i 's/Static Version 1.0/HOT RELOAD SUCCESS/g' "$APP_FILE"
    
    # Wait a moment for autoreload (Flask debug server usually takes < 1s)
    sleep 3
    
    # 5. Test 2: Check response again
    echo "Checking updated response..."
    HTTP_RESPONSE_2=$(curl -s --max-time 2 http://localhost:5000 2>/dev/null || echo "ERROR")
    
    # 6. Check Container ID again
    CONTAINER_ID_END=$(docker compose ps -q web 2>/dev/null || docker ps -q --filter "ancestor=quote-service-web" | head -1)
    
    # Verify results
    if [[ "$HTTP_RESPONSE_2" == *"HOT RELOAD SUCCESS"* ]]; then
        HOT_RELOAD_SUCCESS="true"
    fi
    
    if [ "$CONTAINER_ID_START" == "$CONTAINER_ID_END" ] && [ -n "$CONTAINER_ID_START" ]; then
        CONTAINER_STABLE="true"
    fi
    
    # Restore original file
    mv "$APP_FILE.bak" "$APP_FILE"
else
    echo "App not accessible at localhost:5000"
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_accessible": $APP_ACCESSIBLE,
    "hot_reload_success": $HOT_RELOAD_SUCCESS,
    "container_stable": $CONTAINER_STABLE,
    "has_volumes": $HAS_VOLUMES,
    "has_command_override": $HAS_COMMAND_OVERRIDE,
    "response_initial_len": ${#HTTP_RESPONSE_1},
    "response_updated_len": ${#HTTP_RESPONSE_2},
    "container_id": "$CONTAINER_ID_START",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json