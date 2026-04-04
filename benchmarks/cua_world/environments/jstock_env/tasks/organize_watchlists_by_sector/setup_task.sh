#!/bin/bash
echo "=== Setting up organize_watchlists_by_sector task ==="

# 1. Kill any running JStock instance to ensure clean file operations
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# 2. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Setup JStock Data Directory Paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_BASE="${JSTOCK_DATA_DIR}/watchlist"
MY_WATCHLIST_DIR="${WATCHLIST_BASE}/My Watchlist"

# 4. Clean up previous run artifacts (Remove target watchlists if they exist)
rm -rf "${WATCHLIST_BASE}/Semiconductors"
rm -rf "${WATCHLIST_BASE}/Software & Cloud"
rm -rf "${WATCHLIST_BASE}/Software & Cloud" # handle potential URL encoding variations if any
# Also clean up partial matches just in case
find "${WATCHLIST_BASE}" -maxdepth 1 -name "*Semiconductor*" -type d -exec rm -rf {} +
find "${WATCHLIST_BASE}" -maxdepth 1 -name "*Software*" -type d -exec rm -rf {} +

# 5. Reset "My Watchlist" to the initial 5 stocks
mkdir -p "$MY_WATCHLIST_DIR"

# Write the standard JStock CSV format for the initial state
cat > "${MY_WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
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

echo "Watchlist state reset: 'My Watchlist' contains AAPL, MSFT, GOOGL, AMZN, NVDA."

# 6. Launch JStock
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# 7. Wait for JStock to start
echo "Waiting for JStock to load..."
for i in {1..45}; do
    if wmctrl -l | grep -q "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done
sleep 5 # Extra buffer for Java GUI

# 8. Dismiss "JStock News" dialog if it appears
# Press Enter to clear the default focused "OK" button
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 1
# Fallback Escape
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 1

# 9. Maximize the window
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r 'JStock' -b add,maximized_vert,maximized_horz" 2>/dev/null || true

# 10. Take initial screenshot
echo "Capturing initial state..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="