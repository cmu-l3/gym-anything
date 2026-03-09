#!/bin/bash
set -e
echo "=== Setting up Virtual Feed Aggregation Task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is ready
wait_for_emoncms

# Get Admin Write API Key
APIKEY=$(get_apikey_write)
echo "Using API Key: $APIKEY"

# -----------------------------------------------------------------------
# 1. Clean up any previous state
# -----------------------------------------------------------------------
echo "Cleaning up old feeds..."
# Delete GuestHouse_Total if it exists
EXISTING_ID=$(db_query "SELECT id FROM feeds WHERE name='GuestHouse_Total' AND userid=1" 2>/dev/null | head -1)
if [ -n "$EXISTING_ID" ]; then
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${EXISTING_ID}" > /dev/null
    echo "Deleted existing GuestHouse_Total feed (ID: $EXISTING_ID)"
fi

# Delete source feeds if they exist (to ensure clean IDs and values)
for FEED in guest_lights guest_ac guest_water; do
    FID=$(db_query "SELECT id FROM feeds WHERE name='$FEED' AND userid=1" 2>/dev/null | head -1)
    if [ -n "$FID" ]; then
        curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${FID}" > /dev/null
    fi
done

# -----------------------------------------------------------------------
# 2. Create Source Feeds with fixed values
# -----------------------------------------------------------------------
echo "Creating source feeds..."

# Values: Lights=150.5, AC=1200.2, Water=2500.8 (Total = 3851.5)
# We use PHPFina (engine 5) for source feeds
# Syntax: /feed/create.json?name=...&tag=...&datatype=1&engine=5&options={"interval":10}

# guest_lights
LIGHTS_ID=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=guest_lights&tag=GuestHouse&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=W" | jq '.feedid')
curl -s "${EMONCMS_URL}/feed/insert.json?apikey=${APIKEY}&id=${LIGHTS_ID}&time=$(date +%s)&value=150.5" > /dev/null
echo "Created guest_lights (ID: $LIGHTS_ID) = 150.5 W"

# guest_ac
AC_ID=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=guest_ac&tag=GuestHouse&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=W" | jq '.feedid')
curl -s "${EMONCMS_URL}/feed/insert.json?apikey=${APIKEY}&id=${AC_ID}&time=$(date +%s)&value=1200.2" > /dev/null
echo "Created guest_ac (ID: $AC_ID) = 1200.2 W"

# guest_water
WATER_ID=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=guest_water&tag=GuestHouse&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=W" | jq '.feedid')
curl -s "${EMONCMS_URL}/feed/insert.json?apikey=${APIKEY}&id=${WATER_ID}&time=$(date +%s)&value=2500.8" > /dev/null
echo "Created guest_water (ID: $WATER_ID) = 2500.8 W"

# Save expected values to a temp file for verifier (optional, but good for debugging)
cat > /tmp/expected_values.json << EOF
{
    "guest_lights": 150.5,
    "guest_ac": 1200.2,
    "guest_water": 2500.8,
    "total": 3851.5
}
EOF

# -----------------------------------------------------------------------
# 3. Launch Application
# -----------------------------------------------------------------------
echo "Launching Firefox to Feeds page..."
launch_firefox_to "http://localhost/feed/list" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="