#!/bin/bash
echo "=== Setting up Trypsin Catalytic Triad Analysis ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist and set permissions
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/structures
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/trypsin_triad.png
rm -f /home/ga/PyMOL_Data/trypsin_triad_report.txt

# Record task start timestamp
date +%s > /tmp/trypsin_triad_start_ts

# Launch PyMOL with no structure loaded (agent must fetch it)
launch_pymol

# Maximize PyMOL window
sleep 3
maximize_pymol
sleep 1

# Take initial screenshot showing empty workspace
take_screenshot /tmp/trypsin_triad_start_screenshot.png

echo "=== Setup Complete ==="