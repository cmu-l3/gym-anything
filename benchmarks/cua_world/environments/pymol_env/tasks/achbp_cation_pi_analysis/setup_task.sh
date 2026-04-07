#!/bin/bash
echo "=== Setting up AChBP Cation-Pi Analysis Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1UW6 (AChBP in complex with nicotine)
if [ ! -f "$PDB_DIR/1UW6.pdb" ]; then
    echo "Downloading PDB:1UW6..."
    wget -q "https://files.rcsb.org/download/1UW6.pdb" -O "$PDB_DIR/1UW6.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1UW6.pdb" ]; then
        echo "ERROR: Failed to download 1UW6.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1UW6.pdb"
fi
echo "PDB:1UW6 available at $PDB_DIR/1UW6.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/achbp_cation_pi.png
rm -f /home/ga/PyMOL_Data/achbp_report.txt

# Record task start timestamp
date +%s > /tmp/achbp_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1UW6.pdb"

# Take initial screenshot
sleep 2
take_screenshot /tmp/achbp_start_screenshot.png

echo "=== Setup Complete ==="