#!/bin/bash
echo "=== Setting up Barnase-Barstar BSA Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1BRS (Barnase-Barstar complex)
if [ ! -f "$PDB_DIR/1BRS.pdb" ]; then
    echo "Downloading PDB:1BRS..."
    wget -q "https://files.rcsb.org/download/1BRS.pdb" -O "$PDB_DIR/1BRS.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1BRS.pdb" ]; then
        echo "ERROR: Failed to download 1BRS.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1BRS.pdb"
fi
echo "PDB:1BRS available at $PDB_DIR/1BRS.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/barnase_footprint.png
rm -f /home/ga/PyMOL_Data/bsa_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/barnase_bsa_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1BRS.pdb"

# Take initial screenshot
sleep 2
take_screenshot /tmp/barnase_bsa_start_screenshot.png

echo "=== Setup Complete ==="