#!/bin/bash
echo "=== Setting up KcsA Lipid Interaction Analysis Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1K4C
if [ ! -f "$PDB_DIR/1K4C.pdb" ]; then
    echo "Downloading PDB:1K4C..."
    wget -q "https://files.rcsb.org/download/1K4C.pdb" -O "$PDB_DIR/1K4C.pdb" 2>/dev/null || \
    curl -sL "https://files.rcsb.org/download/1K4C.pdb" -o "$PDB_DIR/1K4C.pdb" 2>/dev/null
    
    if [ ! -s "$PDB_DIR/1K4C.pdb" ]; then
        echo "ERROR: Failed to download 1K4C.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1K4C.pdb"
fi
echo "PDB:1K4C available at $PDB_DIR/1K4C.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/PyMOL_Data/images/kcsa_lipid.png
rm -f /home/ga/PyMOL_Data/kcsa_lipid_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/kcsa_lipid_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1K4C.pdb"

sleep 2
take_screenshot /tmp/kcsa_lipid_start_screenshot.png

echo "=== Setup Complete ==="