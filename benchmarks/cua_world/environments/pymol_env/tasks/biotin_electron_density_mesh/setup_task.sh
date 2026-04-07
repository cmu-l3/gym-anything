#!/bin/bash
echo "=== Setting up Biotin Electron Density Mesh Task ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/sessions
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/biotin_mesh.png
rm -f /home/ga/PyMOL_Data/sessions/biotin_density.pse
rm -f /home/ga/PyMOL_Data/density_report.txt
rm -f /tmp/biotin_mesh_result.json

# Record task start timestamp (integer seconds)
date +%s > /tmp/biotin_mesh_start_ts

# Launch PyMOL with a clean session
# We do not pre-load the PDB file because the agent is instructed to fetch both 
# the coordinates and the map from the EDS server.
launch_pymol

# Take initial screenshot
sleep 2
take_screenshot /tmp/biotin_mesh_start_screenshot.png

echo "=== Setup Complete ==="