#!/bin/bash
echo "=== Setting up Hemoglobin smFRET Fluorophore Design Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Ensure 4HHB is available
if [ ! -f "$PDB_DIR/4HHB.pdb" ]; then
    # Try copying from pre-installed location first
    if [ -f "/opt/pymol_data/structures/4HHB.pdb" ]; then
        cp /opt/pymol_data/structures/4HHB.pdb "$PDB_DIR/"
    else
        echo "Downloading PDB:4HHB..."
        wget -q "https://files.rcsb.org/download/4HHB.pdb" -O "$PDB_DIR/4HHB.pdb" 2>/dev/null
    fi
    chown ga:ga "$PDB_DIR/4HHB.pdb"
fi
echo "PDB:4HHB available at $PDB_DIR/4HHB.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/hemo_fret_sites.png
rm -f /home/ga/PyMOL_Data/hemo_fret_report.txt

# Record task start timestamp
date +%s > /tmp/hemo_smfret_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/4HHB.pdb"

# Wait for render and take initial screenshot
sleep 2
take_screenshot /tmp/hemo_smfret_start_screenshot.png

echo "=== Setup Complete ==="