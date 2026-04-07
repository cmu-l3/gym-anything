#!/bin/bash
echo "=== Setting up generate_network_speed_heatmap task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure dependencies are installed (e.g., matplotlib)
echo "Ensuring matplotlib is installed..."
export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null 2>&1
apt-get install -y python3-matplotlib >/dev/null 2>&1

# Kill any existing SUMO processes just in case
kill_sumo
sleep 1

# Prepare pristine output directory
OUTPUT_DIR="/home/ga/SUMO_Output"
rm -rf "$OUTPUT_DIR"/*
mkdir -p "$OUTPUT_DIR"
chown -R ga:ga "$OUTPUT_DIR"

# Open a terminal for the user (since this is a scripting/CLI task)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=$OUTPUT_DIR &"
    sleep 3
fi

# Maximize the terminal
focus_and_maximize "Terminal"

# Take initial screenshot showing clean state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Output directory prepared at $OUTPUT_DIR"