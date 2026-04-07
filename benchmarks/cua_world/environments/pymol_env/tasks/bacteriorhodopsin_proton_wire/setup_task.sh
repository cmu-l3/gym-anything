#!/bin/bash
echo "=== Setting up Bacteriorhodopsin Proton Wire Analysis Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1C3W (Bacteriorhodopsin ground state)
if [ ! -f "$PDB_DIR/1C3W.pdb" ]; then
    echo "Downloading PDB:1C3W (Bacteriorhodopsin)..."
    wget -q "https://files.rcsb.org/download/1C3W.pdb" -O "$PDB_DIR/1C3W.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1C3W.pdb" ]; then
        echo "ERROR: Failed to download 1C3W.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1C3W.pdb"
fi
echo "PDB:1C3W available at $PDB_DIR/1C3W.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/br_proton_wire.png
rm -f /home/ga/PyMOL_Data/br_pathway_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/br_pathway_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1C3W.pdb"

# Wait and take initial screenshot
sleep 2
take_screenshot /tmp/br_pathway_start_screenshot.png

echo "=== Setup Complete ==="