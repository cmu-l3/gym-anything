#!/bin/bash
echo "=== Setting up solar_storage_monitoring_pipeline ==="
source /workspace/scripts/task_utils.sh

wait_for_emoncms
WRITE_KEY=$(get_apikey_write)

# Remove any existing pvbms/solar/battery feeds for a clean starting state
echo "Cleaning up existing pvbms/solar/battery feeds..."
for fid in $(db_query "SELECT id FROM feeds WHERE userid=1 AND (tag='pvbms' OR tag='solar' OR tag='battery' OR tag='pv' OR name LIKE '%Solar%' OR name LIKE '%Battery%' OR name LIKE '%PV%' OR name LIKE '%kWh%')" 2>/dev/null); do
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${WRITE_KEY}&id=${fid}" >/dev/null 2>&1 || true
done
echo "Old pvbms/solar/battery feeds removed"

# Clear any existing pvbms input process lists
db_query "UPDATE input SET processList='' WHERE userid=1 AND nodeid='pvbms'" 2>/dev/null || true

# Post data to create pvbms inputs if they don't exist yet
# Values are URL-encoded JSON: {"solar_w":2450,"battery_soc":68,"battery_charge_w":550,"battery_discharge_w":0}
curl -s "${EMONCMS_URL}/input/post?apikey=${WRITE_KEY}&node=pvbms&fulljson=%7B%22solar_w%22%3A2450%2C%22battery_soc%22%3A68%2C%22battery_charge_w%22%3A550%2C%22battery_discharge_w%22%3A0%7D" >/dev/null 2>&1 || true
sleep 2
curl -s "${EMONCMS_URL}/input/post?apikey=${WRITE_KEY}&node=pvbms&fulljson=%7B%22solar_w%22%3A2600%2C%22battery_soc%22%3A70%2C%22battery_charge_w%22%3A600%2C%22battery_discharge_w%22%3A0%7D" >/dev/null 2>&1 || true
sleep 2

# Verify pvbms inputs were created
PVBMS_COUNT=$(db_query "SELECT COUNT(*) FROM input WHERE userid=1 AND nodeid='pvbms'" 2>/dev/null | head -1)
echo "pvbms input count: ${PVBMS_COUNT}"

# Record baseline state
INITIAL_FEED_COUNT=$(db_query "SELECT COUNT(*) FROM feeds WHERE userid=1" 2>/dev/null | head -1)
echo "${INITIAL_FEED_COUNT:-0}" > /tmp/initial_feed_count_pvbms

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Navigate to inputs page so agent can start work
launch_firefox_to "http://localhost/input/view" 5

# Take starting screenshot
take_screenshot /tmp/task_solar_storage_start.png

echo "=== Setup complete: solar_storage_monitoring_pipeline ==="
echo "pvbms inputs: solar_w, battery_soc, battery_charge_w, battery_discharge_w"
echo "No feeds or process lists configured — agent must build the pipeline"
