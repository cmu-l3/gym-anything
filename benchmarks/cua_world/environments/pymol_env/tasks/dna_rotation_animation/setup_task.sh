#!/bin/bash
echo "=== Setting up DNA Rotation Animation Task ==="

source /workspace/scripts/task_utils.sh

# Pre-download 1BNA to avoid network issues inside PyMOL, though agent is instructed to fetch it
PDB_DIR="/opt/pymol_data/structures"
mkdir -p "$PDB_DIR"
if [ ! -f "$PDB_DIR/1BNA.pdb" ]; then
    echo "Downloading PDB:1BNA (B-DNA dodecamer)..."
    wget -q "https://files.rcsb.org/download/1BNA.pdb" -O "$PDB_DIR/1BNA.pdb" 2>/dev/null || true
fi

# Ensure output directories exist and are clean
IMAGES_DIR="/home/ga/PyMOL_Data/images"
mkdir -p "$IMAGES_DIR"
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f "$IMAGES_DIR"/*.png
rm -f /home/ga/PyMOL_Data/1bna_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/dna_animation_start_ts

# Launch PyMOL with an empty viewport
launch_pymol

# Wait a moment for UI to settle, then take initial screenshot
sleep 2
take_screenshot /tmp/dna_animation_start_screenshot.png

echo "=== Setup Complete ==="