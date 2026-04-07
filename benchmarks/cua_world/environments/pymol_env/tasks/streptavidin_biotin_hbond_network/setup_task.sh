#!/bin/bash
echo "=== Setting up Streptavidin-Biotin H-bond Network Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1STP (Streptavidin with Biotin)
if [ ! -f "$PDB_DIR/1STP.pdb" ]; then
    echo "Downloading PDB:1STP (Streptavidin-Biotin complex)..."
    wget -q "https://files.rcsb.org/download/1STP.pdb" -O "$PDB_DIR/1STP.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1STP.pdb" ]; then
        echo "ERROR: Failed to download 1STP.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1STP.pdb"
fi
echo "PDB:1STP available at $PDB_DIR/1STP.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/streptavidin_hbond.png
rm -f /home/ga/PyMOL_Data/biotin_hbond_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/1stp_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1STP.pdb"

# Take initial screenshot showing clean state
sleep 2
take_screenshot /tmp/1stp_start_screenshot.png

echo "=== Setup Complete ==="