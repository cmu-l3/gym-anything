#!/bin/bash
echo "=== Setting up PROTAC Ternary Complex Analysis ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/structures
chown -R ga:ga /home/ga/PyMOL_Data

# Pre-download 5T35 as a fallback in case agent's fetch command fails due to network
PDB_DIR="/home/ga/PyMOL_Data/structures"
if [ ! -f "$PDB_DIR/5T35.pdb" ]; then
    echo "Downloading PDB:5T35 fallback..."
    wget -q "https://files.rcsb.org/download/5T35.pdb" -O "$PDB_DIR/5T35.pdb" 2>/dev/null || true
    chown ga:ga "$PDB_DIR/5T35.pdb" 2>/dev/null || true
fi

# Delete any stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/protac_complex.png
rm -f /home/ga/PyMOL_Data/protac_report.txt
rm -f /tmp/protac_result.json

# Record task start timestamp (integer seconds)
date +%s > /tmp/protac_start_ts

# Launch PyMOL with an empty session (agent is instructed to fetch it)
launch_pymol

# Take initial screenshot of empty PyMOL
sleep 2
take_screenshot /tmp/protac_start_screenshot.png

echo "=== Setup Complete ==="