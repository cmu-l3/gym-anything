#!/bin/bash
set -e
echo "=== Setting up reorder_watchlist_priority task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# ============================================================
# Prepare Watchlist Data
# Starting State: AAPL, MSFT, GOOGL, AMZN, NVDA
# Goal State: MSFT, NVDA, AAPL, ...
#
# Path: ~/.jstock/1.0.7/UnitedState/watchlist/My Watchlist/realtimestock.csv
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"

mkdir -p "$WATCHLIST_DIR"

# Create the starting state CSV
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GOOGL","GOOGL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AMZN","AMZN","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Set permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

# Record initial file timestamp/checksum
stat -c %Y "${WATCHLIST_DIR}/realtimestock.csv" > /tmp/initial_file_mtime.txt
sha256sum "${WATCHLIST_DIR}/realtimestock.csv" | awk '{print $1}' > /tmp/initial_file_hash.txt

echo "Watchlist prepared with default order: AAPL, MSFT, GOOGL, AMZN, NVDA"

# ============================================================
# Launch JStock
# ============================================================
if ! pgrep -f "jstock.jar" > /dev/null; then
    echo "Starting JStock..."
    su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"
    
    # Wait for window
    echo "Waiting for JStock window..."
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
            echo "JStock window detected"
            break
        fi
        sleep 1
    done
    
    # Allow extra time for Java initialization and dialogs
    sleep 10
fi

# Dismiss JStock News dialog/startup popups
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "JStock" 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="