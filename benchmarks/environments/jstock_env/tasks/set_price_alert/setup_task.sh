#!/bin/bash
echo "=== Setting up set_price_alert task ==="

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# ============================================================
# Reset watchlist with real US stocks — no alerts set
# Agent must set the Fall Below alert for MSFT at $350
#
# CRITICAL PATHS (verified by running JStock):
#   Country dir: UnitedState  (not "United States")
#   Watchlist:   ~/.jstock/1.0.7/UnitedState/watchlist/My Watchlist/realtimestock.csv
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"

mkdir -p "$WATCHLIST_DIR"

# All Fall Below and Rise Above values are "0.0" (no alerts)
# Agent must set MSFT Fall Below to 350.0
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GOOGL","GOOGL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AMZN","AMZN","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

echo "Watchlist ready with 5 stocks, no alerts set"

# ============================================================
# Launch JStock
# ============================================================
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

echo "Waiting for JStock to start (30 seconds)..."
sleep 30

# Dismiss JStock News dialog (appears on every launch)
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take screenshot to confirm start state
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_start_state.png" 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_start_state.png 2>/dev/null || true

echo "=== set_price_alert task setup complete ==="
