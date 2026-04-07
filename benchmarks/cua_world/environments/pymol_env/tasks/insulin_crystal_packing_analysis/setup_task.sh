#!/bin/bash
echo "=== Setting up Insulin Crystal Packing Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 4INS (porcine insulin)
if [ ! -f "$PDB_DIR/4INS.pdb" ]; then
    echo "Downloading PDB:4INS (porcine insulin)..."
    wget -q "https://files.rcsb.org/download/4INS.pdb" -O "$PDB_DIR/4INS.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/4INS.pdb" ]; then
        echo "ERROR: Failed to download 4INS.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/4INS.pdb"
fi
echo "PDB:4INS available at $PDB_DIR/4INS.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming measure)
rm -f /home/ga/PyMOL_Data/images/insulin_packing.png
rm -f /home/ga/PyMOL_Data/insulin_crystal_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/insulin_crystal_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/4INS.pdb"

sleep 2
take_screenshot /tmp/insulin_crystal_start_screenshot.png

echo "=== Setup Complete ==="