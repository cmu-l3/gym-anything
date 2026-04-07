#!/bin/bash
echo "=== Setting up Amyloid Cross-Beta Analysis Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 2BEG (NMR Ensemble of Abeta fibril)
if [ ! -f "$PDB_DIR/2BEG.pdb" ]; then
    echo "Downloading PDB:2BEG (Amyloid fibril NMR ensemble)..."
    wget -q "https://files.rcsb.org/download/2BEG.pdb" -O "$PDB_DIR/2BEG.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/2BEG.pdb" ]; then
        echo "ERROR: Failed to download 2BEG.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/2BEG.pdb"
fi
echo "PDB:2BEG available at $PDB_DIR/2BEG.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming measure)
rm -f /home/ga/PyMOL_Data/images/amyloid_cross_beta.png
rm -f /home/ga/PyMOL_Data/amyloid_dimensions.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/amyloid_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/2BEG.pdb"

# Let PyMOL load the file and take an initial screenshot
sleep 2
take_screenshot /tmp/amyloid_start_screenshot.png

echo "=== Setup Complete ==="