#!/bin/bash
echo "=== Setting up camera_intrinsic_calibration_sim task ==="

source /workspace/scripts/task_utils.sh

# Create output directories and ensure clean state
EXPORTS_DIR="/home/ga/Documents/CoppeliaSim/exports"
IMG_DIR="$EXPORTS_DIR/calib_images"

mkdir -p "$IMG_DIR"
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove any pre-existing output files (anti-gaming)
rm -f "$EXPORTS_DIR/calibration_poses.csv" 2>/dev/null || true
rm -f "$EXPORTS_DIR/calibration_results.json" 2>/dev/null || true
rm -f "$IMG_DIR"/*.png 2>/dev/null || true

# Record task start timestamp and create a reference marker file
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/camera_calib_start_ts
touch -d "@$TASK_START" /tmp/camera_calib_start_marker

# Launch CoppeliaSim with an empty scene
# The agent must programmatically build the vision sensor and calibration target
echo "Launching CoppeliaSim empty scene..."
launch_coppeliasim

# Focus and maximize window
focus_coppeliasim
maximize_coppeliasim

# Dismiss startup dialogs
sleep 2
dismiss_dialogs

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/camera_calib_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene."
echo "Agent must build the camera/target and run the OpenCV calibration workflow."