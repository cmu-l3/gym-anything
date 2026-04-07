#!/bin/bash
echo "=== Setting up IsPETase Active Site Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 6EQE (IsPETase)
if [ ! -f "$PDB_DIR/6EQE.pdb" ]; then
    echo "Downloading PDB:6EQE (IsPETase)..."
    wget -q "https://files.rcsb.org/download/6EQE.pdb" -O "$PDB_DIR/6EQE.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/6EQE.pdb" ]; then
        echo "ERROR: Failed to download 6EQE.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/6EQE.pdb"
fi
echo "PDB:6EQE available at $PDB_DIR/6EQE.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (Anti-gaming)
rm -f /home/ga/PyMOL_Data/images/petase_active_site.png
rm -f /home/ga/PyMOL_Data/petase_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/petase_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/6EQE.pdb"

# Take initial screenshot
sleep 2
take_screenshot /tmp/petase_start_screenshot.png

echo "=== Setup Complete ==="