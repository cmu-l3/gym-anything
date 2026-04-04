#!/bin/bash
# Setup for calculate_solar_fraction task

source /workspace/scripts/task_utils.sh

echo "=== Setting up calculate_solar_fraction task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Remove any previous report file
rm -f /home/ga/solar_fraction_report.txt

# Ensure Emoncms is running
wait_for_emoncms

# Verify required feeds exist and populate IDs for later verification
# We need to know the IDs to query the API in the export script
APIKEY=$(get_apikey_read)
HOUSE_KWH_ID=$(db_query "SELECT id FROM feeds WHERE name='house_kwh' AND userid=1" | head -1)
SOLAR_KWH_ID=$(db_query "SELECT id FROM feeds WHERE name='solar_kwh' AND userid=1" | head -1)

if [ -z "$HOUSE_KWH_ID" ] || [ -z "$SOLAR_KWH_ID" ]; then
    echo "ERROR: Required feeds (house_kwh, solar_kwh) not found!"
    # In a real scenario, we might trigger a data generation script here if missing
    # For now, we assume the environment setup created them.
    exit 1
fi

echo "Found feeds: house_kwh (ID=$HOUSE_KWH_ID), solar_kwh (ID=$SOLAR_KWH_ID)"

# Store Feed IDs for export_result.sh to use
echo "HOUSE_KWH_ID=$HOUSE_KWH_ID" > /tmp/task_feed_ids.sh
echo "SOLAR_KWH_ID=$SOLAR_KWH_ID" >> /tmp/task_feed_ids.sh
echo "APIKEY=$APIKEY" >> /tmp/task_feed_ids.sh

# Launch Firefox to Emoncms Feeds page
launch_firefox_to "http://localhost/feed/list" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="