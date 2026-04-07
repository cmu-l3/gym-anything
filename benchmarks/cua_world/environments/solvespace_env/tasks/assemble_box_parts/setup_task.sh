#!/bin/bash
set -e
echo "=== Setting up assemble_box_parts task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create parts directory
PARTS_DIR="/home/ga/Documents/SolveSpace/parts"
mkdir -p "$PARTS_DIR"

# Copy official tutorial files from the pre-installed location (real data)
cp /opt/solvespace_samples/base.slvs "$PARTS_DIR/"
cp /opt/solvespace_samples/side.slvs "$PARTS_DIR/"
chown -R ga:ga /home/ga/Documents/SolveSpace

# Verify parts are present and valid
for f in base.slvs side.slvs; do
    if [ ! -f "$PARTS_DIR/$f" ]; then
        echo "ERROR: $PARTS_DIR/$f not found"
        exit 1
    fi
    FSIZE=$(stat -c%s "$PARTS_DIR/$f")
    if [ "$FSIZE" -lt 100 ]; then
        echo "ERROR: $f is too small, likely corrupt"
        exit 1
    fi
done

# Remove any previous assembly output to ensure clean state
rm -f /home/ga/Documents/SolveSpace/box_assembly.slvs

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace fresh (no file argument → new empty sketch)
launch_solvespace ""

# Wait for SolveSpace window to appear
wait_for_solvespace 30
sleep 2

# Maximize the window for clear UI interaction
maximize_solvespace
sleep 1

# Dismiss any potential startup popups
DISPLAY=:1 xdotool key --clearmodifiers Escape 2>/dev/null || true
sleep 0.5

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png
if [ -f /tmp/task_initial_state.png ]; then
    echo "Initial screenshot captured."
else
    echo "WARNING: Could not capture initial screenshot."
fi

echo "=== assemble_box_parts task setup complete ==="