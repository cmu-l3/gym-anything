#!/bin/bash
echo "=== Setting up Cytochrome c Conservation Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1HRC (horse cytochrome c)
if [ ! -f "$PDB_DIR/1HRC.pdb" ] || [ ! -s "$PDB_DIR/1HRC.pdb" ]; then
    echo "Downloading PDB:1HRC (horse cytochrome c)..."
    wget -q "https://files.rcsb.org/download/1HRC.pdb" -O "$PDB_DIR/1HRC.pdb" 2>/dev/null || \
        curl -sL "https://files.rcsb.org/download/1HRC.pdb" -o "$PDB_DIR/1HRC.pdb"
    if [ ! -s "$PDB_DIR/1HRC.pdb" ]; then
        echo "ERROR: Failed to download 1HRC.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1HRC.pdb"
fi

# Download 1YCC (yeast cytochrome c)
if [ ! -f "$PDB_DIR/1YCC.pdb" ] || [ ! -s "$PDB_DIR/1YCC.pdb" ]; then
    echo "Downloading PDB:1YCC (yeast cytochrome c)..."
    wget -q "https://files.rcsb.org/download/1YCC.pdb" -O "$PDB_DIR/1YCC.pdb" 2>/dev/null || \
        curl -sL "https://files.rcsb.org/download/1YCC.pdb" -o "$PDB_DIR/1YCC.pdb"
    if [ ! -s "$PDB_DIR/1YCC.pdb" ]; then
        echo "ERROR: Failed to download 1YCC.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1YCC.pdb"
fi

echo "PDB:1HRC and PDB:1YCC available at $PDB_DIR"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/cytc_conservation.png
rm -f /home/ga/PyMOL_Data/cytc_conservation_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/task_start_time.txt

# Launch PyMOL fresh
kill_pymol
launch_pymol

# Take initial screenshot
sleep 3
maximize_pymol
sleep 1
focus_pymol
take_screenshot /tmp/task_initial_state.png

echo "=== Setup Complete ==="