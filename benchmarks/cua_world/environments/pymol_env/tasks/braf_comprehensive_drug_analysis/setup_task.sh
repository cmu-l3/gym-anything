#!/bin/bash
echo "=== Setting up BRAF Comprehensive Drug Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 3OG7 (BRAF V600E + vemurafenib, DFG-in / Type I)
if [ ! -f "$PDB_DIR/3OG7.pdb" ]; then
    echo "Downloading PDB:3OG7..."
    wget -q "https://files.rcsb.org/download/3OG7.pdb" -O "$PDB_DIR/3OG7.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/3OG7.pdb" ]; then
        echo "ERROR: Failed to download 3OG7.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/3OG7.pdb"
fi

# Download 1UWH (BRAF + sorafenib, DFG-out / Type II)
if [ ! -f "$PDB_DIR/1UWH.pdb" ]; then
    echo "Downloading PDB:1UWH..."
    wget -q "https://files.rcsb.org/download/1UWH.pdb" -O "$PDB_DIR/1UWH.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1UWH.pdb" ]; then
        echo "ERROR: Failed to download 1UWH.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1UWH.pdb"
fi

echo "PDB files cached locally at $PDB_DIR"

# Ensure output directories exist with correct ownership
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/sessions
chown -R ga:ga /home/ga/PyMOL_Data

# Delete all stale output files BEFORE recording the start timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/braf_vemurafenib_pocket.png
rm -f /home/ga/PyMOL_Data/images/braf_dfg_comparison.png
rm -f /home/ga/PyMOL_Data/images/braf_pocket_surface.png
rm -f /home/ga/PyMOL_Data/images/braf_gatekeeper_mutation.png
rm -f /home/ga/PyMOL_Data/braf_drug_analysis_report.txt
rm -f /home/ga/PyMOL_Data/sessions/braf_analysis.pse

# Record task start timestamp (integer seconds) for anti-gaming verification
date +%s > /tmp/braf_comprehensive_start_ts

# Launch PyMOL empty so the agent must fetch/load structures themselves
launch_pymol

# Give the UI time to stabilize, then capture initial screenshot
sleep 3
maximize_pymol
take_screenshot /tmp/braf_comprehensive_start_screenshot.png

echo "=== Setup Complete ==="
