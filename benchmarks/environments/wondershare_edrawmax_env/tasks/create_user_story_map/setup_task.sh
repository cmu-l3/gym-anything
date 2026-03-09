#!/bin/bash
echo "=== Setting up create_user_story_map task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous run artifacts
rm -f /home/ga/Documents/skyhigh_story_map.eddx
rm -f /home/ga/Documents/skyhigh_story_map.png
mkdir -p /home/ga/Documents

# 3. Kill any running instances to start fresh
echo "Killing existing EdrawMax processes..."
kill_edrawmax

# 4. Launch EdrawMax (no file argument -> opens Home/New screen)
echo "Launching EdrawMax..."
launch_edrawmax

# 5. Wait for EdrawMax to load
wait_for_edrawmax 90

# 6. Dismiss startup dialogs (Account Login, File Recovery, Banners)
dismiss_edrawmax_dialogs

# 7. Maximize window
maximize_edrawmax

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="