#!/bin/bash
set -e
echo "=== Setting up Configure Multi-Metric Pipeline Task ==="

source /workspace/scripts/task_utils.sh

# 1. Define Rates and Create Rate File
RATE_FILE="/home/ga/Documents/utility_rates.txt"
COST_RATE="0.24"
CARBON_RATE="0.42"

mkdir -p "$(dirname "$RATE_FILE")"
cat > "$RATE_FILE" << EOF
Utility Rates Configuration
===========================
Electricity Tariff: \$${COST_RATE} / kWh
Grid Carbon Intensity: ${CARBON_RATE} kgCO2 / kWh
EOF
chown ga:ga "$RATE_FILE"

# 2. Ensure Emoncms is ready
wait_for_emoncms

# 3. Create the Input by posting data (simulates sensor)
# Node: facility_meter, Input: main_incomer
echo "Creating input 'main_incomer'..."
APIKEY=$(get_apikey_write)
curl -s "${EMONCMS_URL}/input/post?apikey=${APIKEY}&node=facility_meter&fulljson={\"main_incomer\":0}" > /dev/null

# 4. Clear any existing configuration (idempotency)
# Get Input ID
INPUT_ID=$(db_query "SELECT id FROM input WHERE nodeid='facility_meter' AND name='main_incomer'" 2>/dev/null | head -1)

if [ -n "$INPUT_ID" ]; then
    # Clear process list
    db_query "UPDATE input SET processList='' WHERE id=${INPUT_ID}" 2>/dev/null
fi

# Clean up any pre-existing feeds with the target names to ensure a fresh start
for feed in "facility_power_W" "facility_carbon_kgph" "facility_cost_dollarsph"; do
    FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='$feed'" 2>/dev/null | head -1)
    if [ -n "$FEED_ID" ]; then
        curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${FEED_ID}" > /dev/null
    fi
done

# 5. Launch Firefox to the Inputs page
launch_firefox_to "http://localhost/input/view" 5

# 6. Record start time
date +%s > /tmp/task_start_time.txt

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="