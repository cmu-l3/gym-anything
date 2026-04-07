#!/bin/bash
# setup_task.sh
echo "=== Setting up pr_media_package_generation task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

SOURCE_ORK="/home/ga/Documents/rockets/NDRT_Rocket_2020.ork"
# Fallback to workspace data if missing
if [ ! -f "$SOURCE_ORK" ]; then
    cp /workspace/data/rockets/NDRT_Rocket_2020.ork "$SOURCE_ORK" 2>/dev/null || true
fi

# Ensure directories exist and have proper permissions
mkdir -p /home/ga/Documents/exports
mkdir -p /home/ga/Documents/rockets
chown ga:ga /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/rockets

# Remove any previous outputs to ensure a clean state
rm -f /home/ga/Documents/exports/telemetry_plot.pdf
rm -f /home/ga/Documents/exports/rocket_render.png
rm -f /home/ga/Documents/rockets/pr_rocket.ork

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Kill any existing OpenRocket instances
pkill -f "OpenRocket.jar" 2>/dev/null || true
sleep 2

# Launch OpenRocket directly with the target file
echo "Starting OpenRocket..."
su - ga -c "export DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; java -Xms512m -Xmx2048m -jar /opt/openrocket/OpenRocket.jar '$SOURCE_ORK' > /tmp/openrocket_task.log 2>&1 &"

# Wait for window to appear
echo "Waiting for OpenRocket window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "openrocket\|rocket\|NDRT"; then
        break
    fi
    sleep 1
done
sleep 3

# Maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "openrocket\|rocket\|NDRT" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
# Dismiss any startup dialogs (like update checkers)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for reference
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="