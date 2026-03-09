#!/bin/bash
set -e

echo "=== Setting up segment_watchlist task ==="

# 1. Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# 2. Define Data Paths
# JStock stores data in ~/.jstock/1.0.7/<Country>/watchlist/<WatchlistName>/realtimestock.csv
# Note: "UnitedState" is the directory name for US market in JStock 1.0.7
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_BASE="${JSTOCK_DATA_DIR}/watchlist"
DEFAULT_WATCHLIST="${WATCHLIST_BASE}/My Watchlist"
TARGET_WATCHLIST="${WATCHLIST_BASE}/Core Holdings"

# 3. Clean up previous run artifacts
# Remove "Core Holdings" if it exists to ensure a clean start
if [ -d "$TARGET_WATCHLIST" ]; then
    echo "Removing existing target watchlist..."
    rm -rf "$TARGET_WATCHLIST"
fi

# 4. Reset "My Watchlist" to known starting state (5 stocks)
echo "Resetting My Watchlist..."
mkdir -p "$DEFAULT_WATCHLIST"

cat > "${DEFAULT_WATCHLIST}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GOOGL","GOOGL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AMZN","AMZN","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Fix permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

# 5. Record start time for anti-gaming (file modification check)
date +%s > /tmp/task_start_time.txt

# 6. Launch JStock
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock to start (Java app, can be slow)
echo "Waiting for window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock" > /dev/null; then
        echo "JStock window found."
        break
    fi
    sleep 1
done
sleep 5

# 7. Dismiss "News" dialog if present (Enter key)
# JStock usually shows a "What's New" dialog on startup
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 1
# Press Escape just in case
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 1

# 8. Maximize window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 9. Take initial screenshot
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="