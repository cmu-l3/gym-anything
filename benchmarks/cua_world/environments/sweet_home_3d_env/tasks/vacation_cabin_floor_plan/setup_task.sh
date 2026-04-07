#!/bin/bash
echo "=== Setting up vacation_cabin_floor_plan task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="vacation_cabin_floor_plan"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS="/tmp/${TASK_NAME}_start_ts"
TARGET_FILE="/home/ga/Documents/SweetHome3D/vacation_cabin.sh3d"

# Clean
rm -f "$RESULT_JSON"
rm -f "$TARGET_FILE"

# Record timestamp
date +%s > "$START_TS"
echo "Task start timestamp: $(cat $START_TS)"

# Ensure the target directory exists
mkdir -p /home/ga/Documents/SweetHome3D
chown -R ga:ga /home/ga/Documents/SweetHome3D

# Launch Sweet Home 3D with an empty canvas
# Passing an empty string to setup_sweet_home_3d_task launches a fresh empty project
echo "Launching Sweet Home 3D with empty plan..."
setup_sweet_home_3d_task ""

echo "=== vacation_cabin_floor_plan task setup complete ==="