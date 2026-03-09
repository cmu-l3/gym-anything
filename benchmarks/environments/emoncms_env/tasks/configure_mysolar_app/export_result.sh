#!/bin/bash
echo "=== Exporting Configure MySolar App Result ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# -----------------------------------------------------------------------
# 1. Get the IDs of the reference feeds (Ground Truth)
# -----------------------------------------------------------------------
echo "Retrieving reference feed IDs..."

get_feed_id() {
    local name="$1"
    db_query "SELECT id FROM feeds WHERE name='$name' AND userid=1" 2>/dev/null | head -1
}

ID_SOLAR_POWER=$(get_feed_id "solar_power")
ID_HOUSE_POWER=$(get_feed_id "house_power")
ID_SOLAR_KWH=$(get_feed_id "solar_energy_kwh")
ID_HOUSE_KWH=$(get_feed_id "house_energy_kwh")

echo "Reference IDs: SolarP=$ID_SOLAR_POWER, HouseP=$ID_HOUSE_POWER, SolarK=$ID_SOLAR_KWH, HouseK=$ID_HOUSE_KWH"

# -----------------------------------------------------------------------
# 2. Get the configured values from MySolar App Config
# -----------------------------------------------------------------------
echo "Retrieving MySolar configuration..."

APIKEY=$(get_apikey_read)
# Fetch config via API
CONFIG_JSON=$(curl -s "${EMONCMS_URL}/app/getconfig.json?apikey=${APIKEY}&name=mysolar")

# If API fails, try DB extraction
if [ -z "$CONFIG_JSON" ] || [ "$CONFIG_JSON" = "false" ]; then
    echo "API returned empty config, checking DB..."
    CONFIG_JSON=$(docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -N -e "SELECT config FROM app_config WHERE name='mysolar' AND userid=1" 2>/dev/null || echo "{}")
fi

echo "Config JSON: $CONFIG_JSON"

# -----------------------------------------------------------------------
# 3. Check if configuration was created/modified during task
# -----------------------------------------------------------------------
# We check if the config exists now (it was deleted in setup)
CONFIG_EXISTS="false"
if [ -n "$CONFIG_JSON" ] && [ "$CONFIG_JSON" != "{}" ] && [ "$CONFIG_JSON" != "false" ]; then
    CONFIG_EXISTS="true"
fi

# -----------------------------------------------------------------------
# 4. Export to JSON
# -----------------------------------------------------------------------
take_screenshot /tmp/task_final.png

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_exists": $CONFIG_EXISTS,
    "config_json": $CONFIG_JSON,
    "reference_feeds": {
        "solar_power": "$ID_SOLAR_POWER",
        "house_power": "$ID_HOUSE_POWER",
        "solar_kwh": "$ID_SOLAR_KWH",
        "house_kwh": "$ID_HOUSE_KWH"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="