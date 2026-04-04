#!/bin/bash
set -e
echo "=== Setting up record_portfolio_withdrawal task ==="

# Kill any running JStock instance to ensure clean state
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# ============================================================
# Prepare JStock Data Directory
# We need a clean portfolio state with the deposit summary file ready
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"

mkdir -p "$PORTFOLIO_DIR"
mkdir -p "$WATCHLIST_DIR"

# 1. Setup Watchlist (Standard Requirement for JStock to look normal)
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# 2. Setup Portfolio with some stocks (so it looks used)
# This file tracks stock buys
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
CSVEOF

# 3. Setup Deposit Summary (The Target File)
# Initialize with just the header so we can detect new lines easily
cat > "${PORTFOLIO_DIR}/depositsummary.csv" << 'CSVEOF'
"Date","Amount","Comment"
CSVEOF

# Set Permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

# Record task start time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# ============================================================
# Launch JStock
# ============================================================
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock to start (Java apps are slow)
echo "Waiting for JStock window (up to 45s)..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done
sleep 5

# Dismiss "JStock News" dialog if it appears
# Press Enter (OK) then Escape just in case
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize Window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Navigate to Portfolio Tab
# The tab location depends on resolution, but usually it's the second tab.
# We'll try a mouse click in the tab area (approx x=200, y=80 relative to window, 
# but window is maximized). 
# A more robust way in JStock is Ctrl+2 (if shortcuts exist), but mouse is safer here.
# Assuming 1920x1080, tabs are top left.
# "Stock Watchlist" is Tab 1, "Portfolio Management" is Tab 2.
# Click Tab 2 (approx coordinates: 250, 60)
su - ga -c "DISPLAY=:1 xdotool mousemove 250 60 click 1" 2>/dev/null || true
sleep 2

# Capture Initial State Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="