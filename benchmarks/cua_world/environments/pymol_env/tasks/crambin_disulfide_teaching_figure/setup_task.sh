#!/bin/bash
echo "=== Setting up Crambin Disulfide Teaching Figure Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1CRN (Crambin)
if [ ! -f "$PDB_DIR/1CRN.pdb" ]; then
    echo "Downloading PDB:1CRN (Crambin)..."
    wget -q "https://files.rcsb.org/download/1CRN.pdb" -O "$PDB_DIR/1CRN.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1CRN.pdb" ]; then
        echo "ERROR: Failed to download 1CRN.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1CRN.pdb"
fi
echo "PDB:1CRN available at $PDB_DIR/1CRN.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/crambin_teaching.png
rm -f /home/ga/PyMOL_Data/crambin_structure_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/crambin_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1CRN.pdb"

# Take initial screenshot
sleep 2
take_screenshot /tmp/crambin_start_screenshot.png

echo "=== Setup Complete ==="