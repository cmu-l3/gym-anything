#!/bin/bash
echo "=== Setting up SERT-Paroxetine Binding Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 5I6X (Human SERT with paroxetine)
if [ ! -f "$PDB_DIR/5I6X.pdb" ]; then
    echo "Downloading PDB:5I6X (Human SERT + paroxetine)..."
    wget -q "https://files.rcsb.org/download/5I6X.pdb" -O "$PDB_DIR/5I6X.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/5I6X.pdb" ]; then
        echo "ERROR: Failed to download 5I6X.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/5I6X.pdb"
fi
echo "PDB:5I6X available at $PDB_DIR/5I6X.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (Anti-gaming)
rm -f /home/ga/PyMOL_Data/images/sert_paroxetine.png
rm -f /home/ga/PyMOL_Data/sert_binding_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/sert_paroxetine_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/5I6X.pdb"

sleep 2
take_screenshot /tmp/sert_paroxetine_start_screenshot.png

echo "=== Setup Complete ==="