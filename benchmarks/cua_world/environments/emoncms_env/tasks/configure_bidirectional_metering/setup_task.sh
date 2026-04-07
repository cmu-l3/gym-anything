#!/bin/bash
echo "=== Setting up configure_bidirectional_metering ==="
source /workspace/scripts/task_utils.sh

wait_for_emoncms
WRITE_KEY=$(get_apikey_write)

# -----------------------------------------------------------------------
# Clean up any existing building/grid/solar feeds for a clean state
# -----------------------------------------------------------------------
echo "Cleaning up task-specific feeds (preserving seed data)..."
for fid in $(db_query "SELECT id FROM feeds WHERE userid=1 AND (
    name='solar_power' OR name='solar_energy_kwh'
    OR name='grid_import_power' OR name='grid_import_kwh'
    OR name='grid_export_power' OR name='grid_export_kwh'
    OR name LIKE '%Net Zero%' OR name LIKE '%net_zero%' OR name LIKE '%netzero%'
)" 2>/dev/null); do
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${WRITE_KEY}&id=${fid}" >/dev/null 2>&1 || true
done

# Clear any existing building input process lists
db_query "UPDATE input SET processList='' WHERE userid=1 AND nodeid='building'" 2>/dev/null || true

# Remove any existing Net Zero Tracker dashboard
db_query "DELETE FROM dashboard WHERE userid=1 AND (name LIKE '%Net Zero%' OR name LIKE '%net_zero%' OR name LIKE '%netzero%' OR name LIKE '%Tracker%')" 2>/dev/null || true

# Remove any stale result files BEFORE recording timestamp
rm -f /tmp/configure_bidirectional_metering_result.json 2>/dev/null || true
rm -f /tmp/task_bidir_start.png /tmp/task_bidir_final.png 2>/dev/null || true

# -----------------------------------------------------------------------
# Post data to create building inputs with realistic readings
# grid_meter: signed power (positive=import, negative=export)
# solar_pv:   CT clamp under-reads by 2x, so values are half of true
# -----------------------------------------------------------------------
echo "Posting input data to create building node inputs..."

# Reading 1: Evening — high import, low solar
curl -s "${EMONCMS_URL}/input/post?apikey=${WRITE_KEY}&node=building&fulljson=%7B%22grid_meter%22%3A4500%2C%22solar_pv%22%3A1400%7D" >/dev/null 2>&1 || true
sleep 2

# Reading 2: Solar noon — exporting to grid
curl -s "${EMONCMS_URL}/input/post?apikey=${WRITE_KEY}&node=building&fulljson=%7B%22grid_meter%22%3A-1200%2C%22solar_pv%22%3A2100%7D" >/dev/null 2>&1 || true
sleep 2

# Reading 3: Afternoon — moderate import
curl -s "${EMONCMS_URL}/input/post?apikey=${WRITE_KEY}&node=building&fulljson=%7B%22grid_meter%22%3A3800%2C%22solar_pv%22%3A1850%7D" >/dev/null 2>&1 || true
sleep 2

BUILDING_COUNT=$(db_query "SELECT COUNT(*) FROM input WHERE userid=1 AND nodeid='building'" 2>/dev/null | head -1)
echo "building input count: ${BUILDING_COUNT}"

# -----------------------------------------------------------------------
# Record baseline state
# -----------------------------------------------------------------------
INITIAL_FEED_COUNT=$(db_query "SELECT COUNT(*) FROM feeds WHERE userid=1" 2>/dev/null | head -1)
echo "${INITIAL_FEED_COUNT:-0}" > /tmp/initial_feed_count_bidir
date +%s > /tmp/task_start_timestamp

# -----------------------------------------------------------------------
# Navigate to inputs page
# -----------------------------------------------------------------------
launch_firefox_to "http://localhost/input/view" 5

take_screenshot /tmp/task_bidir_start.png

echo "=== Setup complete: configure_bidirectional_metering ==="
echo "building inputs: grid_meter (signed power), solar_pv (2x under-reading)"
echo "No feeds or process lists configured"
