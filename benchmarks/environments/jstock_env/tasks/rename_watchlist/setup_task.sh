#!/bin/bash
set -e
echo "=== Setting up rename_watchlist task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance to ensure clean state
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# ============================================================
# DATA PREPARATION
# 1. Ensure 'My Watchlist' exists with correct data
# 2. Ensure 'Tech Giants' does NOT exist (clean slate)
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_BASE="${JSTOCK_DATA_DIR}/watchlist"
OLD_WATCHLIST="${WATCHLIST_BASE}/My Watchlist"
NEW_WATCHLIST="${WATCHLIST_BASE}/Tech Giants"

# Clean up target directory if it exists from previous run
if [ -d "$NEW_WATCHLIST" ]; then
    echo "Removing stale target watchlist..."
    rm -rf "$NEW_WATCHLIST"
fi

# Re-create source watchlist
mkdir -p "$OLD_WATCHLIST"

# Populate with real US stocks (AAPL, MSFT, GOOGL, AMZN, NVDA)
cat > "${OLD_WATCHLIST}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GOOGL","GOOGL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AMZN","AMZN","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Ensure permissions are correct
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

# Record initial state for verification
if [ -d "$OLD_WATCHLIST" ]; then
    echo "true" > /tmp/initial_old_exists.txt
else
    echo "false" > /tmp/initial_old_exists.txt
fi

echo "Data preparation complete. 'My Watchlist' restored, 'Tech Giants' removed."

# ============================================================
# APPLICATION LAUNCH
# ============================================================
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for window to appear
echo "Waiting for JStock window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done

# Maximize window (CRITICAL for visibility)
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss JStock News dialog if it appears (Enter key usually works)
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 1
# Fallback escape
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Ensure main window is focused
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="