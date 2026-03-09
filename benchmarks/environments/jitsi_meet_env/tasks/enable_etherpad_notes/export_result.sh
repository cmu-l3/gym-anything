#!/bin/bash
set -e
echo "=== Exporting enable_etherpad_notes results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Etherpad Container Status
ETHERPAD_RUNNING=false
ETHERPAD_CREATED_TS=0
if docker ps --filter "name=etherpad" --format '{{.Names}}' | grep -q "etherpad"; then
    ETHERPAD_RUNNING=true
    # Get creation timestamp
    CREATED_STR=$(docker inspect --format '{{.Created}}' etherpad 2>/dev/null)
    ETHERPAD_CREATED_TS=$(date -d "$CREATED_STR" +%s 2>/dev/null || echo "0")
fi

# 2. Check Jitsi Configuration
# We check if the running jitsi-web container has the config applied
# The config is usually generated into /config/meet.conf.d/config.js inside the container
JITSI_CONFIG_CONTENT=""
if docker ps | grep -q "jitsi-web"; then
    # Try to cat the config from the container
    # Note: Container name might vary slightly depending on compose project name, usually jitsi-web-1 or jitsi_web_1
    WEB_CONTAINER=$(docker ps --format '{{.Names}}' | grep "web" | head -n 1)
    if [ -n "$WEB_CONTAINER" ]; then
        JITSI_CONFIG_CONTENT=$(docker exec "$WEB_CONTAINER" cat /config/config.js 2>/dev/null || echo "")
        # Also check if it's reachable via HTTP
        JITSI_CONFIG_HTTP=$(curl -s "http://localhost:8080/config.js" 2>/dev/null || echo "")
        if [ -n "$JITSI_CONFIG_HTTP" ]; then
            JITSI_CONFIG_CONTENT="$JITSI_CONFIG_HTTP"
        fi
    fi
fi

# 3. Check Jitsi Web Health
WEB_HEALTHY=false
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200"; then
    WEB_HEALTHY=true
fi

# 4. Check Pad Content
# We need the API key from the etherpad container to query the API
PAD_TEXT=""
if [ "$ETHERPAD_RUNNING" = "true" ]; then
    API_KEY=$(docker exec etherpad cat /opt/etherpad-lite/APIKEY.txt 2>/dev/null || echo "")
    
    if [ -n "$API_KEY" ]; then
        # Pad ID is usually the room name for Jitsi
        PAD_ID="WeeklyStandup"
        
        # Try getting text via API
        # Curl inside container or outside? Outside matches exposed port.
        PAD_TEXT=$(curl -s "http://localhost:9001/api/1.2.13/getText?apikey=${API_KEY}&padID=${PAD_ID}" | jq -r '.data.text' 2>/dev/null || echo "")
        
        # Fallback: Check 'weeklystandup' (lowercase) if first failed
        if [ -z "$PAD_TEXT" ] || [ "$PAD_TEXT" = "null" ]; then
             PAD_TEXT=$(curl -s "http://localhost:9001/api/1.2.13/getText?apikey=${API_KEY}&padID=weeklystandup" | jq -r '.data.text' 2>/dev/null || echo "")
        fi
    fi
fi

# 5. Check Screenshot
PROOF_SCREENSHOT="/home/ga/etherpad_integration_proof.png"
SCREENSHOT_EXISTS=false
SCREENSHOT_SIZE=0
if [ -f "$PROOF_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS=true
    SCREENSHOT_SIZE=$(stat -c %s "$PROOF_SCREENSHOT")
fi

# Capture final state screenshot for VLM
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "etherpad_running": $ETHERPAD_RUNNING,
    "etherpad_created_ts": $ETHERPAD_CREATED_TS,
    "jitsi_config_content": $(echo "$JITSI_CONFIG_CONTENT" | jq -R -s '.'),
    "web_healthy": $WEB_HEALTHY,
    "pad_text": $(echo "$PAD_TEXT" | jq -R -s '.'),
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size": $SCREENSHOT_SIZE,
    "screenshot_path": "$PROOF_SCREENSHOT"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"