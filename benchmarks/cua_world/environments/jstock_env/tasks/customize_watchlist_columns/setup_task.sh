#!/bin/bash
echo "=== Setting up customize_watchlist_columns task ==="

# Record task start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# Kill any existing JStock instance to ensure a clean start
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# ============================================================
# Ensure JStock is in a default state regarding UI
# We want to ensure 'Buy'/'Sell' columns are visible initially.
# JStock defaults usually show these. To be safe, we remove
# any user-specific config that might hide them, while preserving
# the watchlist data set up by the environment.
# ============================================================

# JStock stores config in ~/.jstock/1.0.7/ usually as options.xml or jstock.xml
# We will NOT remove the 'UnitedState' directory (data), only top-level config if it exists
# to force JStock to regenerate default UI settings.
CONFIG_DIR="/home/ga/.jstock/1.0.7"
if [ -d "$CONFIG_DIR" ]; then
    echo "Resetting JStock UI configuration..."
    # Remove XML config files but keep directories (like UnitedState)
    find "$CONFIG_DIR" -maxdepth 1 -name "*.xml" -delete 2>/dev/null || true
fi

# Ensure permissions are correct
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \; 2>/dev/null || true
find /home/ga/.jstock -type d -exec chmod 755 {} \; 2>/dev/null || true

# ============================================================
# Launch JStock
# ============================================================
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock to start (Java app, can be slow)
echo "Waiting for JStock window (up to 45s)..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done

# Wait a bit more for UI to fully render
sleep 5

# Dismiss JStock News/Startup dialogs if they appear
# Press Enter (OK) then Escape (Close) just in case
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize window (Critical for VLM visibility of headers)
echo "Maximizing JStock window..."
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Ensure Watchlist tab is focused
# We can't easily programmatically select a tab without pixel coords, 
# but JStock usually starts on the Watchlist or last used tab.
# Since we cleared config, it should default to Watchlist.

# Take initial screenshot for evidence
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="