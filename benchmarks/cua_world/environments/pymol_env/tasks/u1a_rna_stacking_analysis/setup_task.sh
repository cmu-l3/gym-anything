#!/bin/bash
echo "=== Setting up U1A RNA Pi-Stacking Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1URN (U1A-RNA complex)
if [ ! -f "$PDB_DIR/1URN.pdb" ]; then
    echo "Downloading PDB:1URN (U1A-RNA complex)..."
    wget -q "https://files.rcsb.org/download/1URN.pdb" -O "$PDB_DIR/1URN.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1URN.pdb" ]; then
        echo "ERROR: Failed to download 1URN.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1URN.pdb"
fi
echo "PDB:1URN available at $PDB_DIR/1URN.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/u1a_rna_stacking.png
rm -f /home/ga/PyMOL_Data/rna_stacking_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/u1a_stacking_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1URN.pdb"

sleep 2
take_screenshot /tmp/u1a_stacking_start_screenshot.png

echo "=== Setup Complete ==="