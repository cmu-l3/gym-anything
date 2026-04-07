#!/bin/bash
echo "=== Setting up Cross-Kinome Selectivity Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download all three kinase structures
for PDB in 1IEP 1M17 1FIN; do
    if [ ! -f "$PDB_DIR/${PDB}.pdb" ]; then
        echo "Downloading PDB:${PDB}..."
        wget -q "https://files.rcsb.org/download/${PDB}.pdb" -O "$PDB_DIR/${PDB}.pdb" 2>/dev/null
        if [ ! -s "$PDB_DIR/${PDB}.pdb" ]; then
            echo "ERROR: Failed to download ${PDB}.pdb"
            exit 1
        fi
        chown ga:ga "$PDB_DIR/${PDB}.pdb"
    fi
    echo "PDB:${PDB} available at $PDB_DIR/${PDB}.pdb"
done

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/kinase_selectivity.png
rm -f /home/ga/PyMOL_Data/kinase_selectivity_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/kinase_comparison_start_ts

# Launch PyMOL empty — agent must load all 3 structures
launch_pymol

sleep 2
take_screenshot /tmp/kinase_comparison_start_screenshot.png

echo "=== Setup Complete ==="
