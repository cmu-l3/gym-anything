#!/bin/bash
echo "=== Setting up EGFR Kinase Mutation Mapping Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1M17 to ensure it's available locally if RCSB fetch fails
if [ ! -f "$PDB_DIR/1M17.pdb" ]; then
    echo "Downloading PDB:1M17 (EGFR kinase domain bound to erlotinib)..."
    wget -q "https://files.rcsb.org/download/1M17.pdb" -O "$PDB_DIR/1M17.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1M17.pdb" ]; then
        echo "WARNING: Failed to pre-download 1M17.pdb. Agent must fetch it."
    else
        chown ga:ga "$PDB_DIR/1M17.pdb"
    fi
fi

# Ensure output directories exist and are properly owned
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording the timestamp to prevent anti-gaming issues
rm -f /home/ga/PyMOL_Data/images/egfr_mutations.png
rm -f /home/ga/PyMOL_Data/egfr_report.txt

# Record task start timestamp (integer seconds) for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Launch PyMOL empty (the agent is expected to load or fetch the structure)
launch_pymol

# Take initial screenshot of empty state
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="