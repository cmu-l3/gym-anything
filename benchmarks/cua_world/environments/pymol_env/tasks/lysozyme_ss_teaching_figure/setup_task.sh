#!/bin/bash
echo "=== Setting up Lysozyme SS Teaching Figure Task ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/structures
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/lysozyme_ss.png
rm -f /home/ga/PyMOL_Data/lysozyme_ss_report.txt

# Remove any cached 2LYZ files so the agent must fetch it
rm -f /home/ga/PyMOL_Data/structures/2LYZ.pdb 2>/dev/null || true
rm -f /opt/pymol_data/structures/2LYZ.pdb 2>/dev/null || true

# Record task start timestamp (integer seconds)
date +%s > /tmp/lysozyme_ss_start_ts

# Launch PyMOL clean (no structure loaded, agent must fetch)
launch_pymol

# Focus and maximize window
sleep 3
maximize_pymol
sleep 1
focus_pymol
sleep 1

# Take initial screenshot
take_screenshot /tmp/lysozyme_ss_start_screenshot.png

echo "=== Setup Complete ==="