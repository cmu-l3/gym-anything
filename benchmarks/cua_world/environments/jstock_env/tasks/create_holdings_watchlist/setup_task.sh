#!/bin/bash
set -e

echo "=== Setting up create_holdings_watchlist task ==="

# 1. Kill any running instances
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Define Data Paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"
TARGET_WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/Holdings"

# 4. Clean up previous runs
# Remove the target watchlist if it exists so the agent must create it
if [ -d "$TARGET_WATCHLIST_DIR" ]; then
    echo "Removing existing target watchlist..."
    rm -rf "$TARGET_WATCHLIST_DIR"
fi

# 5. Pre-populate Data
mkdir -p "$WATCHLIST_DIR"
mkdir -p "$PORTFOLIO_DIR"

# Default Watchlist: Contains 5 stocks (Mix of owned and not owned)
# Owned: AAPL, MSFT, NVDA
# Not Owned: GOOGL, AMZN
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GOOGL","GOOGL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AMZN","AMZN","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Portfolio: Contains only 3 stocks (AAPL, MSFT, NVDA)
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF

# Create empty companion files to prevent errors
touch "${PORTFOLIO_DIR}/sellportfolio.csv"
touch "${PORTFOLIO_DIR}/depositsummary.csv"
touch "${PORTFOLIO_DIR}/dividendsummary.csv"

# Set permissions
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock

# 6. Launch JStock
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_launch.log 2>&1 &"

# Wait for JStock to start
sleep 20

# Dismiss "JStock News" dialog (Enter key)
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 2

# Maximize window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="