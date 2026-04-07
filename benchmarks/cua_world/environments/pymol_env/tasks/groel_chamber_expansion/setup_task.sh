#!/bin/bash
echo "=== Setting up GroEL Chamber Expansion Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1AON (GroEL-GroES complex)
if [ ! -f "$PDB_DIR/1AON.pdb" ]; then
    echo "Downloading PDB:1AON..."
    wget -q "https://files.rcsb.org/download/1AON.pdb" -O "$PDB_DIR/1AON.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1AON.pdb" ]; then
        echo "ERROR: Failed to download 1AON.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1AON.pdb"
fi
echo "PDB:1AON available at $PDB_DIR/1AON.pdb"

# Ensure output directories exist with correct permissions
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/groel_chamber_sliced.png
rm -f /home/ga/PyMOL_Data/groel_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/groel_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1AON.pdb"

# Allow PyMOL interface to stabilize then capture initial evidence
sleep 2
take_screenshot /tmp/groel_start_screenshot.png

echo "=== Setup Complete ==="