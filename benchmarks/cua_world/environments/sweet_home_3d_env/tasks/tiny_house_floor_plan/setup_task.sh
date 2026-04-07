#!/bin/bash
echo "=== Setting up tiny_house_floor_plan task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="tiny_house_floor_plan"
TARGET_FILE="/home/ga/Documents/SweetHome3D/tiny_house_plan.sh3d"
RESULT_JSON="/tmp/${TASK_NAME}_result.json"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# 1. Clean previous artifacts
echo "Cleaning stale artifacts..."
rm -f "$TARGET_FILE"
rm -f "$RESULT_JSON"
rm -f "$START_TS_FILE"
mkdir -p /home/ga/Documents/SweetHome3D
chown -R ga:ga /home/ga/Documents/SweetHome3D

# 2. Record start time (for anti-gaming)
date +%s > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# 3. Launch Sweet Home 3D with an EMPTY canvas
echo "Launching Sweet Home 3D with a blank canvas..."
setup_sweet_home_3d_task ""

echo "=== tiny_house_floor_plan task setup complete ==="