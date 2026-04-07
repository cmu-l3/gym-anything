#!/bin/bash
echo "=== Setting up airfoiled_fin_fabrication_export task ==="

# Source utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Create required directories
mkdir -p /home/ga/Documents/rockets
mkdir -p /home/ga/Documents/exports

# Clean any existing export files to prevent false positives
rm -f /home/ga/Documents/exports/*.pdf 2>/dev/null || true
rm -f /home/ga/Documents/exports/*.obj 2>/dev/null || true
rm -f /home/ga/Documents/rockets/upgraded_fins.ork 2>/dev/null || true

# Copy the base file to ensure it's in the correct starting state
cp /workspace/data/rockets/dual_parachute_deployment.ork /home/ga/Documents/rockets/dual_parachute_deployment.ork 2>/dev/null || true
chown -R ga:ga /home/ga/Documents

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Start OpenRocket with the target design
if ! pgrep -f "OpenRocket.jar" > /dev/null; then
    echo "Starting OpenRocket..."
    su - ga -c "DISPLAY=:1 JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 java -Xms512m -Xmx2048m -jar /opt/openrocket/OpenRocket.jar /home/ga/Documents/rockets/dual_parachute_deployment.ork > /tmp/openrocket_task.log 2>&1 &"
fi

# Wait for window to appear
echo "Waiting for OpenRocket window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "openrocket\|dual_parachute"; then
        break
    fi
    sleep 1
done
sleep 3

# Maximize the window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "openrocket\|dual_parachute" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss startup dialogs (tips, updates, etc.)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot to document start state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="