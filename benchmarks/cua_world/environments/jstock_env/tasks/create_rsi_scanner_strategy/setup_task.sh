#!/bin/bash
set -e

echo "=== Setting up create_rsi_scanner_strategy task ==="

# 1. Record task start time (critical for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Kill any running JStock instance to ensure clean start
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# 3. Clean up any previous attempts (remove saved scanner configs if possible)
# Note: We act conservatively here to avoid corrupting the install, 
# but we timestamp check specifically to ignore old files.
# If we knew the specific XML file for scanners, we could delete it.
# Instead, we rely on the verifier checking file modification times.

# 4. Launch JStock
echo "Launching JStock..."
# Using setsid to detach from shell, redirecting output
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# 5. Wait for application to load
echo "Waiting for JStock to start (30 seconds)..."
sleep 30

# 6. Handle 'JStock News' startup dialog
# It usually requires clicking 'OK' (Enter) or closing (Escape)
# We try both sequences to be robust.
echo "Dismissing startup dialogs..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# 7. Maximize window (CRITICAL for Agent visibility)
echo "Maximizing JStock window..."
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 8. Focus the window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "JStock" 2>/dev/null || true

# 9. Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="