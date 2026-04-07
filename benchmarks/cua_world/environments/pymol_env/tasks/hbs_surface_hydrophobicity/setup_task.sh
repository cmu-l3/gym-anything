#!/bin/bash
echo "=== Setting up Sickle Cell Hemoglobin Surface Hydrophobicity Analysis ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/structures
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/structures/2HBS_hydrophobic.pdb
rm -f /home/ga/PyMOL_Data/images/hbs_surface.png
rm -f /home/ga/PyMOL_Data/hbs_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/task_start_time.txt

# Launch PyMOL empty (agent must fetch the structure)
launch_pymol

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="