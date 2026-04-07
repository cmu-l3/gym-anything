#!/bin/bash
echo "=== Setting up CDK2 Phosphorylation Network Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1FIN (CDK2-Cyclin A complex)
if [ ! -f "$PDB_DIR/1FIN.pdb" ]; then
    echo "Downloading PDB:1FIN (CDK2-Cyclin A complex)..."
    wget -q "https://files.rcsb.org/download/1FIN.pdb" -O "$PDB_DIR/1FIN.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1FIN.pdb" ]; then
        echo "ERROR: Failed to download 1FIN.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1FIN.pdb"
fi
echo "PDB:1FIN available at $PDB_DIR/1FIN.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/cdk2_activation.png
rm -f /home/ga/PyMOL_Data/cdk2_phospho_report.txt
rm -f /tmp/cdk2_phospho_result.json

# Record task start timestamp (integer seconds)
date +%s > /tmp/cdk2_phospho_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1FIN.pdb"

# Wait for rendering and take initial screenshot
sleep 3
take_screenshot /tmp/cdk2_phospho_start_screenshot.png

echo "=== Setup Complete ==="