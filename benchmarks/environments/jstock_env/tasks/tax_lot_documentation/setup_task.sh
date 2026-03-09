#!/bin/bash
set -e
echo "=== Setting up tax_lot_documentation task ==="

# Kill any running JStock instance to safely modify data files
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# ============================================================
# Configure JStock Data Directories
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"
DOCS_DIR="/home/ga/Documents"

mkdir -p "$WATCHLIST_DIR"
mkdir -p "$PORTFOLIO_DIR"
mkdir -p "$DOCS_DIR"

# Clean up any previous run artifacts
rm -f "$DOCS_DIR/tax_lot_report.txt"

# 1. Setup Watchlist (ensure used stocks are present)
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# 2. Setup Buy Portfolio (Initial State: 3 positions)
# NVDA: 25 shares @ 615.3 on Feb 01, 2024
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF

# 3. Setup Sell Portfolio (Empty/Headers only)
# Agent must add a transaction here via GUI
cat > "${PORTFOLIO_DIR}/sellportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
CSVEOF

# 4. Setup dummy files
touch "${PORTFOLIO_DIR}/depositsummary.csv"
touch "${PORTFOLIO_DIR}/dividendsummary.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock
chown -R ga:ga "$DOCS_DIR"
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

# ============================================================
# Launch JStock
# ============================================================
echo "Starting JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_launch.log 2>&1 &"

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected"
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Dismiss JStock News/Welcome dialog if present
sleep 2
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Navigate to Portfolio Management tab (approximate coordinate click or key nav)
# Assuming typical layout, clicking near the tab area
# Coordinates based on 1920x1080 resolution for the tab bar
DISPLAY=:1 xdotool mousemove 735 158 click 1 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="