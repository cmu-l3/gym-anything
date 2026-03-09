#!/bin/bash
echo "=== Setting up grid_tied_cost_monitoring ==="
source /workspace/scripts/task_utils.sh

wait_for_emoncms
WRITE_KEY=$(get_apikey_write)

# Remove any existing smartmeter/grid feeds for a clean state
echo "Cleaning up existing smartmeter/grid feeds..."
for fid in $(db_query "SELECT id FROM feeds WHERE userid=1 AND (tag='smartmeter' OR tag='grid' OR name LIKE '%Grid%' OR name LIKE '%Import%' OR name LIKE '%Export%')" 2>/dev/null); do
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${WRITE_KEY}&id=${fid}" >/dev/null 2>&1 || true
done

# Clear any existing smartmeter input process lists
db_query "UPDATE input SET processList='' WHERE userid=1 AND nodeid='smartmeter'" 2>/dev/null || true

# Post data to create smartmeter inputs
# import_w: 4200W from grid during a high-demand period
# export_w: 0W (no export right now)
curl -s "${EMONCMS_URL}/input/post?apikey=${WRITE_KEY}&node=smartmeter&fulljson=%7B%22import_w%22%3A4200%2C%22export_w%22%3A0%7D" >/dev/null 2>&1 || true
sleep 2
curl -s "${EMONCMS_URL}/input/post?apikey=${WRITE_KEY}&node=smartmeter&fulljson=%7B%22import_w%22%3A3850%2C%22export_w%22%3A0%7D" >/dev/null 2>&1 || true
sleep 2

SMETER_COUNT=$(db_query "SELECT COUNT(*) FROM input WHERE userid=1 AND nodeid='smartmeter'" 2>/dev/null | head -1)
echo "smartmeter input count: ${SMETER_COUNT}"

# Record baseline
INITIAL_FEED_COUNT=$(db_query "SELECT COUNT(*) FROM feeds WHERE userid=1" 2>/dev/null | head -1)
echo "${INITIAL_FEED_COUNT:-0}" > /tmp/initial_feed_count_grid
date +%s > /tmp/task_start_timestamp

# Navigate to inputs page
launch_firefox_to "http://localhost/input/view" 5

take_screenshot /tmp/task_grid_start.png

echo "=== Setup complete: grid_tied_cost_monitoring ==="
echo "smartmeter inputs: import_w (needs x1.15 calibration), export_w"
echo "No feeds or process lists configured"
