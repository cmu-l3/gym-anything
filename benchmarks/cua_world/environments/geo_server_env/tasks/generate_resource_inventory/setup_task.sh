#!/bin/bash
set -e
echo "=== Setting up generate_resource_inventory task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Remove any previous inventory file to prevent reading old data
rm -f /home/ga/geoserver_inventory.json 2>/dev/null || true

# Ensure GeoServer is running and accessible
verify_geoserver_ready 60 || true
ensure_logged_in

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Result nonce: $NONCE"

# Take initial screenshot of the starting state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="