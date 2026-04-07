#!/bin/bash
echo "=== Setting up DHFR-Methotrexate Density Map Task ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (Anti-gaming)
rm -f /home/ga/PyMOL_Data/images/mtx_density.png
rm -f /home/ga/PyMOL_Data/density_report.txt
rm -f /tmp/density_map_result.json

# Record task start timestamp (integer seconds)
date +%s > /tmp/density_task_start_ts

# Launch PyMOL with an empty session (agent must fetch the data)
launch_pymol

# Wait for PyMOL UI to stabilize
sleep 2

# Take initial screenshot to prove empty/clean state
take_screenshot /tmp/density_task_start_screenshot.png

echo "=== Setup Complete ==="