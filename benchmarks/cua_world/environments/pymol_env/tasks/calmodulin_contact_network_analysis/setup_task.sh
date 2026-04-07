#!/bin/bash
echo "=== Setting up Calmodulin Contact Network Analysis Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"
chown ga:ga /home/ga/PyMOL_Data

# Download 1CLL (Calmodulin) to make it available locally to avoid network issues inside PyMOL
if [ ! -f "$PDB_DIR/1CLL.pdb" ]; then
    echo "Downloading PDB:1CLL (Calmodulin)..."
    wget -q "https://files.rcsb.org/download/1CLL.pdb" -O "$PDB_DIR/1CLL.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1CLL.pdb" ]; then
        echo "ERROR: Failed to download 1CLL.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1CLL.pdb"
fi
echo "PDB:1CLL available at $PDB_DIR/1CLL.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/calmodulin_contacts.txt
rm -f /home/ga/PyMOL_Data/calmodulin_domain_report.txt
rm -f /home/ga/PyMOL_Data/images/calmodulin_domains.png

# Record task start timestamp (integer seconds)
date +%s > /tmp/task_start_ts

# Launch PyMOL with an empty viewport
launch_pymol

sleep 2
take_screenshot /tmp/calmodulin_start_screenshot.png

echo "=== Setup Complete ==="