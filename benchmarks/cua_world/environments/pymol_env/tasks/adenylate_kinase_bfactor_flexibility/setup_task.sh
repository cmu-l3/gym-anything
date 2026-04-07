#!/bin/bash
echo "=== Setting up Adenylate Kinase B-factor Flexibility Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 4AKE (apo adenylate kinase)
if [ ! -f "$PDB_DIR/4AKE.pdb" ]; then
    echo "Downloading PDB:4AKE (apo adenylate kinase)..."
    wget -q "https://files.rcsb.org/download/4AKE.pdb" -O "$PDB_DIR/4AKE.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/4AKE.pdb" ]; then
        echo "ERROR: Failed to download 4AKE.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/4AKE.pdb"
fi
echo "PDB:4AKE available at $PDB_DIR/4AKE.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/PyMOL_Data/images/adk_bfactor.png
rm -f /home/ga/PyMOL_Data/adk_flexibility_report.txt

# Record task start timestamp (integer seconds — Lesson 15)
date +%s > /tmp/adk_bfactor_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/4AKE.pdb"

sleep 2
take_screenshot /tmp/adk_bfactor_start_screenshot.png

echo "=== Setup Complete ==="
