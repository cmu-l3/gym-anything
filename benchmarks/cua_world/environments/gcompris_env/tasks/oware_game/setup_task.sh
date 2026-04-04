#!/bin/bash
set -e
echo "=== Setting up Oware Game task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing GCompris instance
kill_gcompris

# 1. Manage User Data (Backups for change detection)
DB_PATH="/home/ga/.local/share/GCompris/gcompris-qt.db"
CONFIG_PATH="/home/ga/.config/gcompris-qt/GCompris.conf"

# Backup DB if it exists
if [ -f "$DB_PATH" ]; then
    cp "$DB_PATH" /tmp/gcompris_initial.db
    echo "Backed up existing database."
else
    echo "No existing database found."
fi

# Backup Config if it exists
if [ -f "$CONFIG_PATH" ]; then
    cp "$CONFIG_PATH" /tmp/gcompris_initial.conf
fi

# 2. Launch Application
# Launch GCompris to the main menu
launch_gcompris

# 3. Configure Window
maximize_gcompris
sleep 2

# 4. Capture Initial State
take_screenshot /tmp/task_initial.png
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
else
    echo "WARNING: Failed to capture initial screenshot."
fi

echo "=== Oware Game setup complete ==="
echo "GCompris is running at the main menu."
echo "Agent Goal: Navigate to Strategy > Oware, play, and win."