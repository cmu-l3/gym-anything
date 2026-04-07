#!/bin/bash
echo "=== Setting up RNase A Cis-Proline Analysis Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 7RSA (Bovine Pancreatic Ribonuclease A)
if [ ! -f "$PDB_DIR/7RSA.pdb" ]; then
    echo "Downloading PDB:7RSA..."
    wget -q "https://files.rcsb.org/download/7RSA.pdb" -O "$PDB_DIR/7RSA.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/7RSA.pdb" ]; then
        echo "ERROR: Failed to download 7RSA.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/7RSA.pdb"
fi
echo "PDB:7RSA available at $PDB_DIR/7RSA.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/cis_pro93.png
rm -f /home/ga/PyMOL_Data/cis_proline_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/rnase_cis_proline_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/7RSA.pdb"

sleep 2
take_screenshot /tmp/rnase_cis_proline_start_screenshot.png

echo "=== Setup Complete ==="