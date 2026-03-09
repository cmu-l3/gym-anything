#!/bin/bash
echo "=== Setting up verify_portfolio_asset_allocation task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# ============================================================
# Prepare Data Directories
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"
DOCS_DIR="/home/ga/Documents"

mkdir -p "$WATCHLIST_DIR"
mkdir -p "$PORTFOLIO_DIR"
mkdir -p "$DOCS_DIR"

# Cleanup previous run artifacts
rm -f "$DOCS_DIR/allocation_chart.png"

# 1. Setup Watchlist (Tech stocks only initially)
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# 2. Setup Portfolio (Tech heavy)
# AAPL: 100 @ 185.2, MSFT: 50 @ 374.5, NVDA: 25 @ 615.3
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF

# Create empty companion files
echo '"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"' > "${PORTFOLIO_DIR}/sellportfolio.csv"
echo '"Date","Amount","Comment"' > "${PORTFOLIO_DIR}/depositsummary.csv"
echo '"Code","Symbol","Date","Amount","Comment"' > "${PORTFOLIO_DIR}/dividendsummary.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;
chown ga:ga "$DOCS_DIR"

# ============================================================
# Launch Application
# ============================================================
echo "Starting JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for window
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected"
        break
    fi
    sleep 1
done

# Dismiss News Dialog (Enter key)
sleep 5
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 1

# Maximize
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="