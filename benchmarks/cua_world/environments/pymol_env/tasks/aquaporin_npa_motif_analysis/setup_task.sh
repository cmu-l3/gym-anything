#!/bin/bash
echo "=== Setting up Aquaporin NPA Motif Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1J4N
if [ ! -f "$PDB_DIR/1J4N.pdb" ]; then
    echo "Downloading PDB:1J4N (bovine Aquaporin-1)..."
    wget -q "https://files.rcsb.org/download/1J4N.pdb" -O "$PDB_DIR/1J4N.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1J4N.pdb" ]; then
        echo "ERROR: Failed to download 1J4N.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1J4N.pdb"
fi
echo "PDB:1J4N available at $PDB_DIR/1J4N.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/PyMOL_Data/images/aqp1_npa_motifs.png
rm -f /home/ga/PyMOL_Data/aqp1_pore_report.txt

# Record task start timestamp
date +%s > /tmp/aqp1_npa_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1J4N.pdb"

sleep 2
take_screenshot /tmp/aqp1_npa_start_screenshot.png

echo "=== Setup Complete ==="