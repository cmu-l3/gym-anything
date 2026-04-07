#!/bin/bash
echo "=== Setting up Carbonic Anhydrase Zinc Coordination Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1CA2 (Human Carbonic Anhydrase II)
if [ ! -f "$PDB_DIR/1CA2.pdb" ]; then
    echo "Downloading PDB:1CA2..."
    wget -q "https://files.rcsb.org/download/1CA2.pdb" -O "$PDB_DIR/1CA2.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1CA2.pdb" ]; then
        echo "ERROR: Failed to download 1CA2.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1CA2.pdb"
fi
echo "PDB:1CA2 available at $PDB_DIR/1CA2.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/ca2_zinc_coordination.png
rm -f /home/ga/PyMOL_Data/ca2_zinc_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/ca2_zinc_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1CA2.pdb"

sleep 2
take_screenshot /tmp/ca2_zinc_start_screenshot.png

echo "=== Setup Complete ==="