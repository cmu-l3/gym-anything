#!/bin/bash
echo "=== Setting up configure_candlestick_chart task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# Ensure Watchlist exists with NVDA
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"
mkdir -p "$WATCHLIST_DIR"

# Pre-populate watchlist with NVDA and others
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Ensure permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

# ============================================================
# Clear previous chart settings if possible
# ============================================================
# JStock stores chart preferences in config files. 
# We remove specific config files to force defaults (Line chart)
rm -f "/home/ga/.jstock/1.0.7/config/chart.xml" 2>/dev/null || true
# Also check for options.xml where some global preferences live
# We won't delete options.xml as it might break other things, but ensuring clean state helps.

# ============================================================
# Launch JStock
# ============================================================
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock window
echo "Waiting for JStock to start..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "JStock"; then
        echo "JStock window detected"
        break
    fi
    sleep 1
done

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss news dialog if it appears
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="