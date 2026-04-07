#!/bin/bash
echo "=== Setting up SOD1 Electrostatic Funnel Analysis ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/structures
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/PyMOL_Data/images/sod1_electrostatic.png
rm -f /home/ga/PyMOL_Data/sod1_electrostatic_report.txt

# Remove 2SOD if it exists to force the agent to fetch/download it
rm -f /home/ga/PyMOL_Data/structures/2SOD.pdb
rm -f /home/ga/PyMOL_Data/structures/2sod.pdb

# Record task start timestamp (integer seconds) for anti-gaming verification
date +%s > /tmp/sod1_electrostatic_start_ts

# Kill any existing PyMOL instances
kill_pymol

# Launch PyMOL empty (agent must fetch the structure)
echo "Launching PyMOL..."
su - ga -c "DISPLAY=:1 QT_QPA_PLATFORM=xcb setsid pymol -q > /tmp/pymol_launch.log 2>&1 &"

# Wait for PyMOL window to appear
wait_for_pymol 30
sleep 3
maximize_pymol

# Take initial screenshot
take_screenshot /tmp/sod1_electrostatic_start_screenshot.png

echo "=== Setup Complete ==="