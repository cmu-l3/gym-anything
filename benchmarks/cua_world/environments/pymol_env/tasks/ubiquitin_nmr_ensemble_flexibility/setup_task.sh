#!/bin/bash
echo "=== Setting up Ubiquitin NMR Ensemble Flexibility Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1D3Z (human ubiquitin NMR solution structure)
if [ ! -f "$PDB_DIR/1D3Z.pdb" ]; then
    echo "Downloading PDB:1D3Z (human ubiquitin NMR ensemble)..."
    wget -q "https://files.rcsb.org/download/1D3Z.pdb" -O "$PDB_DIR/1D3Z.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1D3Z.pdb" ]; then
        echo "ERROR: Failed to download 1D3Z.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1D3Z.pdb"
fi
echo "PDB:1D3Z available at $PDB_DIR/1D3Z.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (preventing anti-gaming)
rm -f /home/ga/PyMOL_Data/images/ubiquitin_ensemble.png
rm -f /home/ga/PyMOL_Data/ubiquitin_flexibility_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/ubq_nmr_start_ts

# Launch PyMOL with the multi-model structure pre-loaded
launch_pymol_with_file "$PDB_DIR/1D3Z.pdb"

# Let the UI stabilize and take an initial evidence screenshot
sleep 2
take_screenshot /tmp/ubq_nmr_start_screenshot.png

echo "=== Setup Complete ==="