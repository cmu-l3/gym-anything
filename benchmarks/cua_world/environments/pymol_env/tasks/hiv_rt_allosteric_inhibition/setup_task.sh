#!/bin/bash
echo "=== Setting up HIV-1 RT Allosteric Inhibition Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1VRT (HIV-1 Reverse Transcriptase with nevirapine)
if [ ! -f "$PDB_DIR/1VRT.pdb" ]; then
    echo "Downloading PDB:1VRT (HIV-1 RT with NVP)..."
    wget -q "https://files.rcsb.org/download/1VRT.pdb" -O "$PDB_DIR/1VRT.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1VRT.pdb" ]; then
        echo "ERROR: Failed to download 1VRT.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1VRT.pdb"
fi
echo "PDB:1VRT available at $PDB_DIR/1VRT.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (critical for anti-gaming)
rm -f /home/ga/PyMOL_Data/images/rt_allostery.png
rm -f /home/ga/PyMOL_Data/rt_allostery_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/rt_allostery_start_ts

# Launch PyMOL with the target structure
launch_pymol_with_file "$PDB_DIR/1VRT.pdb"

sleep 2
take_screenshot /tmp/rt_allostery_start_screenshot.png

echo "=== Setup Complete ==="