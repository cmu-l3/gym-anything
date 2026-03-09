#!/bin/bash
echo "=== Setting up configure_email_alerts task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# ============================================================
# Clean up previous configuration
# We want the agent to start with NO email settings
# ============================================================
JSTOCK_CONFIG_DIR="/home/ga/.jstock/1.0.7"

# JStock often stores options in files like 'jstock.xml' or 'options.xml'
# or within the 'config' subdirectory. We'll try to sanitize common config files.
# Since we don't want to wipe the whole directory (which has the watchlist),
# we will just do a best-effort grep to ensure clean state or rely on overwrite.
# For this task, we assume the agent overwrites. 
# However, to be safe, we can backup and grep-sed if needed, but JStock
# typically overwrites XML entries.

# Ensure the directory exists
mkdir -p "$JSTOCK_CONFIG_DIR"
chown -R ga:ga /home/ga/.jstock

# ============================================================
# Launch JStock
# ============================================================
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

echo "Waiting for JStock to start (30 seconds)..."
sleep 30

# Dismiss JStock News dialog (appears on every launch)
# Press Enter to click the OK/Continue button
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2

# Press Escape as fallback
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize window (CRITICAL for agent visibility)
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take screenshot of initial state (for evidence)
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial_state.png 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="