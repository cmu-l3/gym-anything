#!/bin/bash
echo "=== Setting up Multi-Module Refactor Task ==="
source /workspace/scripts/task_utils.sh

# Copy monolith source to /home/ga/
echo "[SETUP] Copying ecommerce-monolith to /home/ga/..."
rm -rf /home/ga/ecommerce-monolith
cp -r /workspace/data/ecommerce-monolith /home/ga/ecommerce-monolith
chown -R ga:ga /home/ga/ecommerce-monolith

# Remove any previous refactored project
rm -rf /home/ga/ecommerce-refactored

# Record start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task started at: $(cat /tmp/task_start_timestamp)"

# Ensure Eclipse is running
ensure_display_ready

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
