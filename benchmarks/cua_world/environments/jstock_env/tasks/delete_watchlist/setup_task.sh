#!/bin/bash
set -e
echo "=== Setting up delete_watchlist task ==="

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Kill any running JStock
pkill -f "jstock" 2>/dev/null || true
sleep 3

# Define paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_BASE="${JSTOCK_DATA_DIR}/watchlist"

# Ensure base directory exists
mkdir -p "$WATCHLIST_BASE"

# ============================================================
# 1. Setup 'My Watchlist' (Default, Keep)
# ============================================================
mkdir -p "${WATCHLIST_BASE}/My Watchlist"
cat > "${WATCHLIST_BASE}/My Watchlist/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GOOGL","GOOGL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AMZN","AMZN","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# ============================================================
# 2. Setup 'Tech Stocks' (Keep)
# ============================================================
mkdir -p "${WATCHLIST_BASE}/Tech Stocks"
cat > "${WATCHLIST_BASE}/Tech Stocks/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"META","META","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AMD","AMD","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# ============================================================
# 3. Setup 'Energy Stocks' (Target to Delete)
# ============================================================
mkdir -p "${WATCHLIST_BASE}/Energy Stocks"
cat > "${WATCHLIST_BASE}/Energy Stocks/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"XOM","XOM","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"CVX","CVX","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"COP","COP","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"SLB","SLB","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"EOG","EOG","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Set correct ownership and permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

# Record initial state for verification
ls -1d "${WATCHLIST_BASE}"/*/ 2>/dev/null | wc -l > /tmp/initial_watchlist_count.txt
echo "Initial watchlist count: $(cat /tmp/initial_watchlist_count.txt)"

# Launch JStock
echo "Launching JStock..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock to fully load
echo "Waiting for JStock to start (30 seconds)..."
sleep 30

# Dismiss startup dialog (JStock News)
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 3

# Maximize and focus JStock window
for window_name in "JStock" "jstock" "Stock"; do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "$window_name" -b add,maximized_vert,maximized_horz 2>/dev/null; then
        echo "Maximized $window_name"
        break
    fi
done
sleep 1

# Take initial screenshot
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial_state.png" 2>/dev/null || true

echo "=== Task setup complete ==="