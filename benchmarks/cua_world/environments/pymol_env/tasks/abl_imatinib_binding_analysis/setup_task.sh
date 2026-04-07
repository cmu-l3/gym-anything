#!/bin/bash
echo "=== Setting up ABL-Imatinib Binding Analysis ==="

source /workspace/scripts/task_utils.sh

# Download 1IEP (ABL kinase with imatinib/STI-571)
PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"
if [ ! -f "$PDB_DIR/1IEP.pdb" ]; then
    echo "Downloading PDB:1IEP..."
    wget -q "https://files.rcsb.org/download/1IEP.pdb" -O "$PDB_DIR/1IEP.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1IEP.pdb" ]; then
        echo "ERROR: Failed to download 1IEP.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1IEP.pdb"
fi
echo "PDB:1IEP available at $PDB_DIR/1IEP.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/abl_imatinib.png
rm -f /home/ga/PyMOL_Data/abl_binding_report.txt

# Record task start timestamp (integer seconds — Lesson 15)
date +%s > /tmp/abl_imatinib_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1IEP.pdb"

# Take initial screenshot
sleep 2
take_screenshot /tmp/abl_imatinib_start_screenshot.png

echo "=== Setup Complete ==="
