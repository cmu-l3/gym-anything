#!/bin/bash
set -e
echo "=== Setting up convert_watchlist_to_portfolio task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# ============================================================
# 1. CLEANUP: Remove target portfolio if it exists
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
TARGET_PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/Starter_Positions"

if [ -d "$TARGET_PORTFOLIO_DIR" ]; then
    echo "Removing existing target portfolio..."
    rm -rf "$TARGET_PORTFOLIO_DIR"
fi

# ============================================================
# 2. SETUP: Ensure "My Watchlist" has the required 5 stocks
# ============================================================
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"
mkdir -p "$WATCHLIST_DIR"

# Write known state to watchlist
# Format verified from JStock 1.0.7
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
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

# ============================================================
# 3. LAUNCH: Start JStock
# ============================================================
echo "Starting JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for window
echo "Waiting for JStock window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock" > /dev/null; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done
sleep 5

# Dismiss the "JStock News" dialog if it appears (Enter key)
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1
# Just in case, try Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus window
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="