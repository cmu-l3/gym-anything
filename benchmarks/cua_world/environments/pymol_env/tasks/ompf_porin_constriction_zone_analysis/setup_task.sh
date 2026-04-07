#!/bin/bash
echo "=== Setting up OmpF Porin Constriction Zone Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/structures
chown -R ga:ga /home/ga/PyMOL_Data

# Remove the target structure if it was cached previously to force agent to fetch it
rm -f /home/ga/PyMOL_Data/structures/2OMF.pdb
rm -f /home/ga/PyMOL_Data/structures/2omf.pdb

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/ompf_constriction_zone.png
rm -f /home/ga/PyMOL_Data/ompf_pore_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/ompf_task_start_ts

# Launch PyMOL with an empty session
launch_pymol

# Wait a moment for UI to settle and take initial screenshot
sleep 2
take_screenshot /tmp/ompf_start_screenshot.png

echo "=== Setup Complete ==="