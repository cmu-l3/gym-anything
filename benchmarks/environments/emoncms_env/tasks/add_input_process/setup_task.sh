#!/bin/bash
# Task setup: add_input_process
# Clears the heatpump input process list so the agent can add one.

source /workspace/scripts/task_utils.sh

echo "=== Setting up add_input_process task ==="

wait_for_emoncms

APIKEY=$(get_apikey_write)

# Get the heatpump input id
HEATPUMP_ID=$(db_query "SELECT id FROM input WHERE name='heatpump' AND userid=1" 2>/dev/null | head -1)
if [ -n "$HEATPUMP_ID" ]; then
    # Clear process list for heatpump input via MySQL (API unreliable for this)
    db_query "UPDATE input SET processList='' WHERE id=${HEATPUMP_ID}" 2>/dev/null || true
    echo "Cleared process list for heatpump input (id=${HEATPUMP_ID})"
else
    echo "Warning: heatpump input not found, it may need to be re-created by posting data"
    # Re-post data to create the input
    curl -s "${EMONCMS_URL}/input/post?apikey=${APIKEY}&node=home&fulljson={\"heatpump\":800}" >/dev/null 2>&1 || true
    sleep 2
fi

# Remove "Heat Pump Log" feed if it already exists (clean state)
EXISTING=$(db_query "SELECT id FROM feeds WHERE name='Heat Pump Log' AND userid=1" 2>/dev/null | head -1)
if [ -n "$EXISTING" ]; then
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY}&id=${EXISTING}" >/dev/null 2>&1 || true
    echo "Removed existing 'Heat Pump Log' feed (id=${EXISTING})"
fi

# Navigate to Inputs page
launch_firefox_to "http://localhost/input/view" 5

# Take a starting screenshot
take_screenshot /tmp/task_add_input_process_start.png

echo "=== Task setup complete: add_input_process ==="
