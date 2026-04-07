#!/bin/bash
echo "=== Setting up SARS-CoV-2 N501Y Mutagenesis Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"
chown ga:ga "$PDB_DIR"

# Download 6M0J (WT SARS-CoV-2 RBD + ACE2)
if [ ! -f "$PDB_DIR/6M0J.pdb" ]; then
    echo "Downloading PDB:6M0J..."
    wget -q "https://files.rcsb.org/download/6M0J.pdb" -O "$PDB_DIR/6M0J.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/6M0J.pdb" ]; then
        echo "ERROR: Failed to download 6M0J.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/6M0J.pdb"
fi
echo "PDB:6M0J available at $PDB_DIR/6M0J.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/structures/6m0j_N501Y.pdb
rm -f /home/ga/PyMOL_Data/images/n501y_interaction.png
rm -f /home/ga/PyMOL_Data/n501y_report.txt

# Record task start timestamp 
date +%s > /tmp/n501y_mutagenesis_start_ts

# Launch PyMOL with the WT structure
launch_pymol_with_file "$PDB_DIR/6M0J.pdb"

# Maximize window and wait for load
sleep 3
maximize_pymol
take_screenshot /tmp/n501y_mutagenesis_start_screenshot.png

echo "=== Setup Complete ==="