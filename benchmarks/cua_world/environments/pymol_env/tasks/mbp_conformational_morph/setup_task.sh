#!/bin/bash
echo "=== Setting up MBP Conformational Morph Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Pre-download 1OMP (apo MBP) and 1ANF (holo MBP) to ensure they are available
for PDB_ID in "1OMP" "1ANF"; do
    if [ ! -f "$PDB_DIR/${PDB_ID}.pdb" ]; then
        echo "Downloading PDB:${PDB_ID}..."
        wget -q "https://files.rcsb.org/download/${PDB_ID}.pdb" -O "$PDB_DIR/${PDB_ID}.pdb" 2>/dev/null
        if [ ! -s "$PDB_DIR/${PDB_ID}.pdb" ]; then
            echo "ERROR: Failed to download ${PDB_ID}.pdb"
            exit 1
        fi
        chown ga:ga "$PDB_DIR/${PDB_ID}.pdb"
    fi
done

echo "PDB:1OMP and PDB:1ANF are available at $PDB_DIR"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/mbp_morph.pdb
rm -f /home/ga/PyMOL_Data/images/mbp_superposition.png
rm -f /home/ga/PyMOL_Data/mbp_morph_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/mbp_morph_start_ts

# Launch PyMOL without any pre-loaded structures to force the agent to start from scratch
launch_pymol

sleep 2
take_screenshot /tmp/mbp_morph_start_screenshot.png

echo "=== Setup Complete ==="