#!/bin/bash
echo "=== Setting up buffer_populated_places task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up previous run artifacts (CRITICAL)
EXPORT_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$EXPORT_DIR"
rm -f "$EXPORT_DIR/city_buffers."* 2>/dev/null || true
echo "Cleaned up previous output files in $EXPORT_DIR"

# Ensure data directory permissions
chown -R ga:ga "/home/ga/gvsig_data"

# 2. Verify input data exists
INPUT_FILE="/home/ga/gvsig_data/cities/ne_110m_populated_places.shp"
if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: Input file not found at $INPUT_FILE"
    # Attempt to restore from backup or download if missing (fail-safe)
    # For now, just exit with error to fail setup
    exit 1
fi

# 3. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 4. Launch gvSIG
# We want a clean state (Project Manager open, no View), so we launch without a project file
kill_gvsig
echo "Launching gvSIG Desktop..."
launch_gvsig ""

# 5. Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="