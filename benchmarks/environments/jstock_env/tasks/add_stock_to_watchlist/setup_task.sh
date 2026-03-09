#!/bin/bash
echo "=== Setting up add_stock_to_watchlist task ==="

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# ============================================================
# Ensure watchlist has the pre-populated real US stocks
# (without TSLA — agent must add it)
#
# CRITICAL PATHS (verified by running JStock):
#   Country dir: UnitedState  (not "United States")
#   Watchlist:   ~/.jstock/1.0.7/UnitedState/watchlist/My Watchlist/realtimestock.csv
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"

mkdir -p "$WATCHLIST_DIR"

# Watchlist CSV format (verified from running JStock):
#   - First line: "timestamp=0"
#   - All values double-quoted
#   - 17 columns
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

echo "Watchlist reset to 5 stocks (AAPL, MSFT, GOOGL, AMZN, NVDA) — TSLA not added yet"

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

# Maximize window for better visibility
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take screenshot to confirm start state
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_start_state.png" 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_start_state.png 2>/dev/null || true

echo "=== add_stock_to_watchlist task setup complete ==="
