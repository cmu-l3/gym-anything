#!/bin/bash
set -e
echo "=== Setting up historical_eclipse_planetarium_render task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/sobral_eclipse_1919.png
rm -f /home/ga/Documents/relativity_stars.txt
rm -f /tmp/task_result.json
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# 3. Ensure KStars is running
ensure_kstars_running
sleep 3

# 4. Dismiss any dialogs that might be lingering
for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# 5. Maximize and focus the application
maximize_kstars
focus_kstars
sleep 1

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Recreate 1919 solar eclipse from Sobral, Brazil"
echo "Target outputs: ~/Documents/sobral_eclipse_1919.png and ~/Documents/relativity_stars.txt"