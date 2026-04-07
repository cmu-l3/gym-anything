#!/bin/bash
echo "=== Setting up CRISPR-Cas9 PAM Recognition Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 4UN3 (SpCas9 complex)
if [ ! -f "$PDB_DIR/4UN3.pdb" ]; then
    echo "Downloading PDB:4UN3 (SpCas9 complex)..."
    wget -q "https://files.rcsb.org/download/4UN3.pdb" -O "$PDB_DIR/4UN3.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/4UN3.pdb" ]; then
        echo "ERROR: Failed to download 4UN3.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/4UN3.pdb"
fi
echo "PDB:4UN3 available at $PDB_DIR/4UN3.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/PyMOL_Data/images/cas9_pam_recognition.png
rm -f /home/ga/PyMOL_Data/cas9_pam_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/cas9_pam_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/4UN3.pdb"

sleep 2
take_screenshot /tmp/cas9_pam_start_screenshot.png

echo "=== Setup Complete ==="