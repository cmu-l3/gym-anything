#!/bin/bash
echo "=== Setting up GCN4 Coiled-Coil Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/structures

# Remove any pre-existing 2ZTA files to force the agent to fetch it
rm -f /home/ga/PyMOL_Data/structures/2ZTA*
rm -f /home/ga/PyMOL_Data/structures/2zta*

# Delete stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/gcn4_coiled_coil.png
rm -f /home/ga/PyMOL_Data/gcn4_coiled_coil_report.txt

chown -R ga:ga /home/ga/PyMOL_Data

# Record task start timestamp (integer seconds)
date +%s > /tmp/gcn4_start_ts

# Launch PyMOL empty (no pre-loaded structure)
launch_pymol

# Take initial screenshot
sleep 2
take_screenshot /tmp/gcn4_start_screenshot.png

echo "=== Setup Complete ==="