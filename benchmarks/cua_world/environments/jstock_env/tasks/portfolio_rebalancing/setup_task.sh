#!/bin/bash
set -e

echo "=== Setting up portfolio_rebalancing task ==="

# Kill any running JStock instance
pkill -f "jstock" 2>/dev/null || true
sleep 2

# Clean up previous task artifacts
rm -f /home/ga/Desktop/rebalance_sells_feb2024.csv 2>/dev/null || true

# Delete stale task start file BEFORE recording timestamp (anti-gaming)
rm -f /tmp/task_start_ts_portfolio_rebalancing

# Record task start timestamp AFTER cleanup
TS=$(date +%s)
echo "$TS" > /tmp/task_start_ts_portfolio_rebalancing
echo "Task start timestamp: $TS"

# ============================================================
# Set up JStock directory structure
# ============================================================
JSTOCK_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_DIR="$JSTOCK_DIR/portfolios/My Portfolio"
WATCHLIST_DIR="$JSTOCK_DIR/watchlist/My Watchlist"

mkdir -p "$PORTFOLIO_DIR"
mkdir -p "$WATCHLIST_DIR"

# ============================================================
# Watchlist: include all portfolio stocks so agent can
# reference them easily from the watchlist view
# ============================================================
cat > "$WATCHLIST_DIR/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"JNJ","JNJ","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"XOM","XOM","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# ============================================================
# Buy portfolio: tech-heavy initial holdings (real Jan 2, 2024
# closing prices from Yahoo Finance).
# AAPL $185.64, MSFT $374.51, NVDA $495.22, JNJ $152.10, XOM $99.64
# ============================================================
cat > "$PORTFOLIO_DIR/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 2, 2024","150.0","185.64","0.0","27846.0","0.0","-185.64","-27846.0","-100.0","0.0","0.0","0.0","27846.0","-27846.0","-100.0",""
"MSFT","Microsoft Corporation","Jan 2, 2024","80.0","374.51","0.0","29960.8","0.0","-374.51","-29960.8","-100.0","0.0","0.0","0.0","29960.8","-29960.8","-100.0",""
"NVDA","NVIDIA Corporation","Jan 2, 2024","35.0","495.22","0.0","17332.7","0.0","-495.22","-17332.7","-100.0","0.0","0.0","0.0","17332.7","-17332.7","-100.0",""
"JNJ","Johnson & Johnson","Jan 2, 2024","40.0","152.10","0.0","6084.0","0.0","-152.10","-6084.0","-100.0","0.0","0.0","0.0","6084.0","-6084.0","-100.0",""
"XOM","Exxon Mobil Corporation","Jan 2, 2024","60.0","99.64","0.0","5978.4","0.0","-99.64","-5978.4","-100.0","0.0","0.0","0.0","5978.4","-5978.4","-100.0",""
CSVEOF

# ============================================================
# Sell portfolio: EMPTY at task start (agent will add entries)
# ============================================================
cat > "$PORTFOLIO_DIR/sellportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
CSVEOF

# Empty companion files
cat > "$PORTFOLIO_DIR/depositsummary.csv" << 'CSVEOF'
"Date","Amount","Comment"
CSVEOF

cat > "$PORTFOLIO_DIR/dividendsummary.csv" << 'CSVEOF'
"Code","Symbol","Date","Amount","Comment"
CSVEOF

# Set permissions
chown -R ga:ga /home/ga/.jstock 2>/dev/null || true
find /home/ga/.jstock -type f -exec chmod 644 {} \; 2>/dev/null || true
find /home/ga/.jstock -type d -exec chmod 755 {} \; 2>/dev/null || true

# ============================================================
# Record initial state (anti-gaming baseline)
# ============================================================
# Record initial buy entry count (5 holdings, no sell entries)
echo "5" > /tmp/initial_buy_count_portfolio_rebalancing
echo "0" > /tmp/initial_sell_count_portfolio_rebalancing
echo "AAPL MSFT NVDA JNJ XOM" > /tmp/initial_buy_codes_portfolio_rebalancing
ls "$JSTOCK_DIR/portfolios/" > /tmp/initial_portfolio_names_portfolio_rebalancing 2>/dev/null || echo "My Portfolio" > /tmp/initial_portfolio_names_portfolio_rebalancing
ls "$JSTOCK_DIR/watchlist/" > /tmp/initial_watchlist_names_portfolio_rebalancing 2>/dev/null || echo "My Watchlist" > /tmp/initial_watchlist_names_portfolio_rebalancing

echo "Portfolio data pre-populated:"
echo "  Buy portfolio: 5 tech-heavy holdings (AAPL 150 shares, MSFT 80, NVDA 35, JNJ 40, XOM 60)"
echo "  Sell portfolio: EMPTY"
echo "  Desktop: no rebalance_sells_feb2024.csv"

# ============================================================
# Launch JStock
# ============================================================
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_portfolio_rebalancing.log 2>&1 &"
sleep 10

# Dismiss JStock News dialog
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize window
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a JStock" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz" 2>/dev/null || true
sleep 2

# Take initial screenshot
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_start_portfolio_rebalancing.png" 2>/dev/null || true

echo "=== portfolio_rebalancing setup complete ==="
exit 0
