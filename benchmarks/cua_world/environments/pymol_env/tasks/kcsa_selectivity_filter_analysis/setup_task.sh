#!/bin/bash
echo "=== Setting up KcsA Selectivity Filter Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1K4C (KcsA Potassium Channel)
if [ ! -f "$PDB_DIR/1K4C.pdb" ]; then
    echo "Downloading PDB:1K4C..."
    wget -q "https://files.rcsb.org/download/1K4C.pdb" -O "$PDB_DIR/1K4C.pdb" || \
        curl -sL "https://files.rcsb.org/download/1K4C.pdb" -o "$PDB_DIR/1K4C.pdb"
    
    if [ ! -s "$PDB_DIR/1K4C.pdb" ]; then
        echo "ERROR: Failed to download 1K4C.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1K4C.pdb"
fi

echo "PDB:1K4C available at $PDB_DIR/1K4C.pdb"

# Ensure output directories exist and permissions are correct
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete any pre-existing output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/kcsa_selectivity_filter.png
rm -f /home/ga/PyMOL_Data/kcsa_filter_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/kcsa_start_ts

# Launch a clean PyMOL session (no structure loaded, agent must do it)
launch_pymol

# Wait for PyMOL to fully open and maximize
sleep 3
maximize_pymol
sleep 1
focus_pymol
sleep 1

# Take an initial screenshot proving clean starting state
take_screenshot /tmp/kcsa_start_screenshot.png

echo "=== Setup Complete ==="