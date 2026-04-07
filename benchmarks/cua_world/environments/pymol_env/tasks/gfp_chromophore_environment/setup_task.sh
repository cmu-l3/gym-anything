#!/bin/bash
echo "=== Setting up GFP Chromophore Environment Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1GFL (WT GFP) from RCSB
if [ ! -f "$PDB_DIR/1GFL.pdb" ]; then
    echo "Downloading PDB:1GFL (WT GFP)..."
    wget -q "https://files.rcsb.org/download/1GFL.pdb" -O "$PDB_DIR/1GFL.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1GFL.pdb" ]; then
        echo "ERROR: Failed to download 1GFL.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1GFL.pdb"
fi
echo "PDB:1GFL available at $PDB_DIR/1GFL.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (Anti-gaming check)
rm -f /home/ga/PyMOL_Data/images/gfp_chromophore.png
rm -f /home/ga/PyMOL_Data/gfp_environment_report.txt

# Record task start timestamp in integer seconds
date +%s > /tmp/gfp_chromophore_start_ts

# Launch PyMOL with the loaded structure
launch_pymol_with_file "$PDB_DIR/1GFL.pdb"

# Let application UI stabilize before taking starting screenshot
sleep 2
take_screenshot /tmp/gfp_chromophore_start_screenshot.png

echo "=== Setup Complete ==="