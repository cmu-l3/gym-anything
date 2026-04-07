#!/bin/bash
echo "=== Setting up Streptavidin-Biotin Stereo Visualization Task ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming check)
rm -f /home/ga/PyMOL_Data/images/streptavidin_stereo.png
rm -f /home/ga/PyMOL_Data/streptavidin_pocket.txt

# Record task start timestamp
date +%s > /tmp/streptavidin_start_ts

# Launch PyMOL completely empty (agent must fetch 1STP on its own)
launch_pymol

# Wait to ensure the window exists and is fully rendered
sleep 3
maximize_pymol
sleep 1

# Take initial screenshot showing the empty PyMOL state
take_screenshot /tmp/streptavidin_start_screenshot.png

echo "=== Setup Complete ==="