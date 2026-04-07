#!/bin/bash
echo "=== Setting up HIV-1 Protease Water Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1HSG (HIV-1 protease + indinavir)
if [ ! -f "$PDB_DIR/1HSG.pdb" ]; then
    echo "Downloading PDB:1HSG..."
    wget -q "https://files.rcsb.org/download/1HSG.pdb" -O "$PDB_DIR/1HSG.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1HSG.pdb" ]; then
        echo "ERROR: Failed to download 1HSG.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1HSG.pdb"
fi
echo "PDB:1HSG available at $PDB_DIR/1HSG.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/hiv_water_network.png
rm -f /home/ga/PyMOL_Data/hiv_water_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/hiv_water_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1HSG.pdb"

# Take initial screenshot
sleep 2
take_screenshot /tmp/hiv_water_start_screenshot.png

echo "=== Setup Complete ==="