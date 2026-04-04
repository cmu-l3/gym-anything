#!/bin/bash
set -e

echo "=== Setting up verify_auto_reconnection task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming (file timestamp checks)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Jitsi Meet is running
echo "Checking Jitsi Meet status..."
cd /home/ga/jitsi
docker compose up -d
wait_for_http "http://localhost:8080" 60

# 3. Clean up previous artifacts
rm -f /home/ga/reconnecting_state.png
rm -f /home/ga/restored_state.png

# 4. Open Terminal for the agent (positioned on left)
# usage of gnome-terminal might differ slightly by version, but standard in ubuntu-gnome
if ! pgrep -f "gnome-terminal" > /dev/null; then
    DISPLAY=:1 gnome-terminal --working-directory="/home/ga/jitsi" --geometry=80x24+0+0 &
    sleep 2
fi
DISPLAY=:1 wmctrl -r "Terminal" -e 0,0,0,900,600 2>/dev/null || true

# 5. Open Firefox (positioned on right/overlapping)
restart_firefox "http://localhost:8080" 5
# Resize to not fully cover terminal if possible, or maximize and let agent switch
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -e 0,100,100,1200,800 2>/dev/null || true
focus_firefox

# 6. Take setup screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Instructions:"
echo "1. Join room 'ResilienceTest' in Firefox."
echo "2. Stop JVB in terminal: docker compose stop jvb"
echo "3. Screenshot error state -> ~/reconnecting_state.png"
echo "4. Start JVB in terminal: docker compose start jvb"
echo "5. Wait for reconnect, screenshot restored state -> ~/restored_state.png"