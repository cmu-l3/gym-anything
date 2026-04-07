#!/bin/bash
echo "=== Setting up Telomeric G-Quadruplex Analysis ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (Anti-gaming check)
rm -f /home/ga/PyMOL_Data/images/g_quadruplex.png
rm -f /home/ga/PyMOL_Data/k_coordination_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/g_quadruplex_start_ts

# Launch PyMOL with an empty session
# The task description requires the agent to fetch 1KF1 themselves
launch_pymol

# Wait a moment to ensure PyMOL UI is ready
sleep 3
maximize_pymol
sleep 1

# Take initial screenshot showing empty PyMOL session
take_screenshot /tmp/g_quadruplex_start_screenshot.png

echo "=== Setup Complete ==="