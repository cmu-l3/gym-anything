#!/bin/bash
echo "=== Setting up Antibody-Antigen Interface Mapping ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1DVF (D1.3 antibody-lysozyme complex)
if [ ! -f "$PDB_DIR/1DVF.pdb" ]; then
    echo "Downloading PDB:1DVF (D1.3 antibody-lysozyme complex)..."
    wget -q "https://files.rcsb.org/download/1DVF.pdb" -O "$PDB_DIR/1DVF.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1DVF.pdb" ]; then
        echo "ERROR: Failed to download 1DVF.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1DVF.pdb"
fi
echo "PDB:1DVF available at $PDB_DIR/1DVF.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/PyMOL_Data/images/dvf_interface.png
rm -f /home/ga/PyMOL_Data/dvf_interface_report.txt

# Record task start timestamp (integer seconds — Lesson 15)
date +%s > /tmp/dvf_interface_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1DVF.pdb"

sleep 2
take_screenshot /tmp/dvf_interface_start_screenshot.png

echo "=== Setup Complete ==="
