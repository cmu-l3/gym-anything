#!/bin/bash
echo "=== Exporting MyElectric Configuration ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get the config from the database
# Emoncms stores app config in the 'app_config' table column 'config' (JSON)
RAW_CONFIG=$(db_query "SELECT config FROM app_config WHERE app='myelectric' AND userid=1")

# If empty, try checking via API (alternative verification)
APIKEY=$(get_apikey_read)
API_CONFIG=$(curl -s "${EMONCMS_URL}/app/getconfig.json?apikey=${APIKEY}&app=myelectric" 2>/dev/null || echo "{}")

# 3. Get Feed IDs to verify mapping
# We need to know what ID 'house_power' and 'house_energy_kwh' actually have
POWER_FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='house_power' AND userid=1")
ENERGY_FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='house_energy_kwh' AND userid=1")

# 4. Check if config was saved during task
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# We don't have a file timestamp for DB records easily, but we know we cleared it in setup.
# So if it exists now, it was created during the task.
CONFIG_EXISTS="false"
if [ -n "$RAW_CONFIG" ] && [ "$RAW_CONFIG" != "null" ]; then
    CONFIG_EXISTS="true"
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config_exists": $CONFIG_EXISTS,
    "raw_config_db": $(if [ -n "$RAW_CONFIG" ]; then echo "'$RAW_CONFIG'"; else echo "{}"; fi),
    "api_config": $API_CONFIG,
    "feed_map": {
        "house_power_id": "${POWER_FEED_ID}",
        "house_energy_kwh_id": "${ENERGY_FEED_ID}"
    },
    "task_start": $TASK_START,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move and set permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. content of /tmp/task_result.json:"
cat /tmp/task_result.json