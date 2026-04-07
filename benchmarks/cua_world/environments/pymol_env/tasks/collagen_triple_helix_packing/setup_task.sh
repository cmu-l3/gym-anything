#!/bin/bash
echo "=== Setting up Collagen Triple Helix Packing Task ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/structures
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (Anti-gaming measure)
rm -f /home/ga/PyMOL_Data/images/collagen_core.png
rm -f /home/ga/PyMOL_Data/collagen_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/collagen_start_ts

# Launch PyMOL with an empty viewport
# The agent is expected to fetch PDB 1BKV directly
launch_pymol

# Give PyMOL a moment to initialize the GUI
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/collagen_start_screenshot.png

echo "=== Setup Complete ==="