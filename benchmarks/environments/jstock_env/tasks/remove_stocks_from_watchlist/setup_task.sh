#!/bin/bash
set -e
echo "=== Setting up remove_stocks_from_watchlist task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any existing JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# ============================================================
# Prepare Watchlist Data
# ------------------------------------------------------------
# CRITICAL: We must ensure the file exists with the 5 specific stocks
# so we can verify their removal later.
# Path: ~/.jstock/1.0.7/UnitedState/watchlist/My Watchlist/realtimestock.csv
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"

mkdir -p "$WATCHLIST_DIR"

# Create the initial CSV with 5 stocks
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GOOGL","GOOGL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AMZN","AMZN","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Save a copy of this initial state for comparison in export_result.sh
cp "${WATCHLIST_DIR}/realtimestock.csv" /tmp/initial_watchlist.csv

# Set correct permissions
chown -R ga:ga /home/ga/.jstock
chmod 644 "${WATCHLIST_DIR}/realtimestock.csv"

echo "Watchlist prepared with 5 stocks: AAPL, MSFT, GOOGL, AMZN, NVDA"

# ============================================================
# Launch JStock
# ============================================================
echo "Launching JStock..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock window to appear
echo "Waiting for JStock to start..."
for i in {1..45}; do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "jstock"; then
        echo "JStock window detected after ${i}s"
        break
    fi
    sleep 1
done

# Wait for Java to fully render GUI
sleep 15

# Dismiss JStock News dialog (appears on every launch)
# Press Enter to click "OK"
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
# Fallback escape
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize window for consistent VLM view
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Focus JStock window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "JStock" 2>/dev/null || true
sleep 1

# Take screenshot of initial state
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png" 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured"
else
    echo "WARNING: Initial screenshot failed"
fi

echo "=== Task setup complete ==="