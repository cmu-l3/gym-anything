#!/bin/bash
set -e
echo "=== Setting up Reconcile Missing Transaction task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# ============================================================
# 1. Setup JStock Data (Initial State: AAPL + MSFT only)
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"

mkdir -p "$WATCHLIST_DIR"
mkdir -p "$PORTFOLIO_DIR"

# Ensure watchlist has the relevant stocks so they can be selected
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GOOGL","GOOGL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Create Portfolio with ONLY AAPL and MSFT (GOOGL is missing)
# Note: Values are strings in quotes
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
CSVEOF

# Create empty companion files to prevent errors
echo '"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"' > "${PORTFOLIO_DIR}/sellportfolio.csv"
echo '"Date","Amount","Comment"' > "${PORTFOLIO_DIR}/depositsummary.csv"
echo '"Code","Symbol","Date","Amount","Comment"' > "${PORTFOLIO_DIR}/dividendsummary.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;

# ============================================================
# 2. Create Broker Statement CSV
# ============================================================
DOCS_DIR="/home/ga/Documents"
mkdir -p "$DOCS_DIR"

# Statement includes AAPL, MSFT, AND GOOGL
# Date format is deliberately different (ISO) to force agent to adapt
cat > "${DOCS_DIR}/jan_2024_statement.csv" << 'CSVEOF'
Date,Ticker,Company,Action,Quantity,Price,Total,Currency
2024-01-15,AAPL,Apple Inc.,BUY,100,185.20,18520.00,USD
2024-01-15,MSFT,Microsoft Corp.,BUY,50,374.50,18725.00,USD
2024-01-22,GOOGL,Alphabet Inc.,BUY,20,148.50,2970.00,USD
CSVEOF

chown ga:ga "${DOCS_DIR}/jan_2024_statement.csv"

# ============================================================
# 3. Launch JStock
# ============================================================
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_launch.log 2>&1 &"

# Wait for JStock to appear
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done
sleep 5

# Dismiss news dialog if present
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize JStock
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Navigate to Portfolio tab (approximate click location for 1920x1080)
# Tab bar is usually near top. Portfolio is often the 2nd or 3rd tab.
# We'll try clicking "Portfolio Management" text if possible, or just focus window.
# Clicking specific coordinate for Portfolio tab (verified from env info ~ 735, 158)
su - ga -c "DISPLAY=:1 xdotool mousemove 735 158 click 1" 2>/dev/null || true
sleep 2

# Open file manager to show the document exists (optional hint)
su - ga -c "DISPLAY=:1 nautilus /home/ga/Documents &" 2>/dev/null || true
sleep 3
DISPLAY=:1 wmctrl -r "Documents" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Bring JStock back to focus
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="