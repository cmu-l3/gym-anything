#!/bin/bash
set -e
echo "=== Setting up adjust_stock_split task ==="

# 1. Kill any existing JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# 2. Define Data Paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"

mkdir -p "$WATCHLIST_DIR"
mkdir -p "$PORTFOLIO_DIR"

# 3. Pre-populate Watchlist (Required for JStock to recognize symbols)
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# 4. Pre-populate Portfolio with PRE-SPLIT data
# AAPL: 100 units @ 185.2
# MSFT: 50 units @ 374.5
# NVDA: 25 units @ 615.3
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF

# Create empty companion files to prevent JStock errors
touch "${PORTFOLIO_DIR}/sellportfolio.csv"
touch "${PORTFOLIO_DIR}/depositsummary.csv"
touch "${PORTFOLIO_DIR}/dividendsummary.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock

# 5. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 6. Launch JStock
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# 7. Wait for Window and Initialize
echo "Waiting for JStock window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock" > /dev/null; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done

# Wait for splash screen to clear and app to load
sleep 10

# Dismiss "JStock News" dialog (Enter key usually works)
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 2

# Maximize Window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 8. Switch to "Portfolio Management" tab
# Verified coordinate click for 1920x1080 default layout
# The tab is usually the second one.
DISPLAY=:1 xdotool mousemove 735 158 click 1 2>/dev/null || true
sleep 2

# 9. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="