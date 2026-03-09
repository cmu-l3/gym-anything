#!/bin/bash
set -e
echo "=== Setting up change_look_and_feel task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance to ensure clean start
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# ============================================================
# Reset JStock configuration to ensure default theme
# ============================================================
JSTOCK_CONFIG_DIR="/home/ga/.jstock/1.0.7"
mkdir -p "$JSTOCK_CONFIG_DIR"

# JStock stores options in options.xml. Removing it forces defaults.
if [ -f "$JSTOCK_CONFIG_DIR/options.xml" ]; then
    echo "Removing existing options.xml to reset theme..."
    rm "$JSTOCK_CONFIG_DIR/options.xml"
fi

# Ensure basic data exists so the app looks normal (not empty)
COUNTRY_DIR="$JSTOCK_CONFIG_DIR/UnitedState"
WATCHLIST_DIR="$COUNTRY_DIR/watchlist/My Watchlist"
mkdir -p "$WATCHLIST_DIR"

# Populate a simple watchlist
cat > "$WATCHLIST_DIR/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GOOGL","GOOGL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Fix permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

# ============================================================
# Launch JStock
# ============================================================
echo "Starting JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for window to appear
echo "Waiting for JStock window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done

# Wait for app to settle
sleep 5

# Dismiss the "JStock News" dialog that appears on startup
# Press Enter to click OK
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 1
# Press Escape as backup
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 1

# Maximize window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Focus the window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "JStock" 2>/dev/null || true

# Take screenshot of initial state (Default Theme)
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="