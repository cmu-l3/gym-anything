#!/bin/bash
echo "=== Setting up consolidate_watchlists task ==="

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# Prepare Watchlists
# Path: ~/.jstock/1.0.7/UnitedState/watchlist/
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_BASE="${JSTOCK_DATA_DIR}/watchlist"
TECH_DIR="${WATCHLIST_BASE}/Tech"
AUTO_DIR="${WATCHLIST_BASE}/Auto"

# Clean up any existing state
rm -rf "$WATCHLIST_BASE"
mkdir -p "$TECH_DIR"
mkdir -p "$AUTO_DIR"

# 1. Create 'Tech' watchlist: AAPL, MSFT, TSLA
cat > "${TECH_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"TSLA","TSLA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# 2. Create 'Auto' watchlist: F, GM, TSLA
cat > "${AUTO_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"F","F","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GM","GM","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"TSLA","TSLA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Ensure correct permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

echo "Watchlists prepared: Tech (3 stocks), Auto (3 stocks)"

# ============================================================
# Launch JStock
# ============================================================
if ! pgrep -f "jstock.jar" > /dev/null; then
    echo "Starting JStock..."
    su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"
    
    # Wait for JStock to start
    echo "Waiting for JStock to initialize..."
    sleep 30

    # Dismiss 'JStock News' or startup dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
    sleep 2
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 2
fi

# Ensure window is maximized
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Focus window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "JStock" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="