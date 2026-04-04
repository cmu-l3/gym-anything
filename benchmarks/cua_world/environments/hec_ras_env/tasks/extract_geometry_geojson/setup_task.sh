#!/bin/bash
echo "=== Setting up extract_geometry_geojson task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project to ensure .g04 exists
restore_muncie_project

# 2. Verify geometry file exists
GEOM_FILE="$MUNCIE_DIR/Muncie.g04"
if [ ! -f "$GEOM_FILE" ]; then
    echo "ERROR: Geometry file $GEOM_FILE not found!"
    # Fallback search
    GEOM_FILE=$(find "$MUNCIE_DIR" -name "*.g04" | head -1)
fi

if [ -z "$GEOM_FILE" ]; then
    echo "CRITICAL: No .g04 file found. Task cannot proceed."
    exit 1
fi

echo "Geometry file located at: $GEOM_FILE"

# 3. Create results directory
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Open terminal in project directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Display file info to agent
type_in_terminal "ls -lh Muncie.g04"
type_in_terminal "head -n 20 Muncie.g04"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="