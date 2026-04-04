#!/bin/bash
echo "=== Setting up multizone_submetering_configuration ==="
source /workspace/scripts/task_utils.sh

wait_for_emoncms
WRITE_KEY=$(get_apikey_write)

# Remove any existing zone feeds to ensure clean state
echo "Cleaning up existing zone feeds..."
for fid in $(db_query "SELECT id FROM feeds WHERE userid=1 AND (tag='hvac' OR tag='lighting' OR tag='sockets' OR tag='zone' OR name LIKE '%HVAC%' OR name LIKE '%Lighting%' OR name LIKE '%Socket%' OR name LIKE '%Zone%')" 2>/dev/null); do
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${WRITE_KEY}&id=${fid}" >/dev/null 2>&1 || true
done

# Clear any existing zone input process lists
db_query "UPDATE input SET processList='' WHERE userid=1 AND nodeid IN ('zone_hvac','zone_lighting','zone_sockets')" 2>/dev/null || true

# Post data to create zone inputs
# zone_hvac: HVAC running at ~3500W
curl -s "${EMONCMS_URL}/input/post?apikey=${WRITE_KEY}&node=zone_hvac&fulljson=%7B%22power_w%22%3A3480%7D" >/dev/null 2>&1 || true
sleep 1
# zone_lighting: lights at ~850W
curl -s "${EMONCMS_URL}/input/post?apikey=${WRITE_KEY}&node=zone_lighting&fulljson=%7B%22power_w%22%3A847%7D" >/dev/null 2>&1 || true
sleep 1
# zone_sockets: desks/equipment at ~1200W
curl -s "${EMONCMS_URL}/input/post?apikey=${WRITE_KEY}&node=zone_sockets&fulljson=%7B%22power_w%22%3A1195%7D" >/dev/null 2>&1 || true
sleep 2

# Record baseline
INITIAL_FEED_COUNT=$(db_query "SELECT COUNT(*) FROM feeds WHERE userid=1" 2>/dev/null | head -1)
echo "${INITIAL_FEED_COUNT:-0}" > /tmp/initial_feed_count_zones
date +%s > /tmp/task_start_timestamp

# Navigate to inputs page
launch_firefox_to "http://localhost/input/view" 5

take_screenshot /tmp/task_zones_start.png

echo "=== Setup complete: multizone_submetering_configuration ==="
echo "Zone inputs created: zone_hvac/power_w, zone_lighting/power_w, zone_sockets/power_w"
echo "No feeds or process lists configured"
