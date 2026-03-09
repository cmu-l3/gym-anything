#!/bin/bash
set -e

echo "=== Setting up tax_lot_portfolio_tracking task ==="

# Kill any running JStock instance
pkill -f "jstock" 2>/dev/null || true
sleep 2

# Record task start timestamp
rm -f /tmp/task_start_ts_tax_lot_portfolio_tracking
TS=$(date +%s)
echo "$TS" > /tmp/task_start_ts_tax_lot_portfolio_tracking
echo "Task start timestamp: $TS"

JSTOCK_DIR="/home/ga/.jstock/1.0.7/UnitedState"

# Remove any pre-existing task-specific data (anti-gaming)
rm -rf "$JSTOCK_DIR/portfolios/Tax Lots 2024" 2>/dev/null || true
rm -rf "$JSTOCK_DIR/watchlist/Tax Watch 2024" 2>/dev/null || true

# Ensure "My Portfolio" exists as baseline (unrelated existing data)
mkdir -p "$JSTOCK_DIR/portfolios/My Portfolio"
cat > "$JSTOCK_DIR/portfolios/My Portfolio/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"SPY","SPDR S&P 500 ETF","Jan 2, 2024","100.0","470.46","0.0","47046.0","0.0","-470.46","-47046.0","-100.0","0.0","0.0","0.0","47046.0","-47046.0","-100.0","core index allocation"
CSVEOF
cat > "$JSTOCK_DIR/portfolios/My Portfolio/sellportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
CSVEOF
cat > "$JSTOCK_DIR/portfolios/My Portfolio/depositsummary.csv" << 'CSVEOF'
"Date","Amount","Comment"
CSVEOF
cat > "$JSTOCK_DIR/portfolios/My Portfolio/dividendsummary.csv" << 'CSVEOF'
"Code","Symbol","Date","Amount","Comment"
CSVEOF

# Ensure baseline watchlist exists
mkdir -p "$JSTOCK_DIR/watchlist/My Watchlist"
cat > "$JSTOCK_DIR/watchlist/My Watchlist/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"SPY","SPY","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Set permissions
chown -R ga:ga /home/ga/.jstock 2>/dev/null || true
find /home/ga/.jstock -type f -exec chmod 644 {} \; 2>/dev/null || true
find /home/ga/.jstock -type d -exec chmod 755 {} \; 2>/dev/null || true

# Record initial state (anti-gaming baseline)
ls "$JSTOCK_DIR/portfolios/" > /tmp/initial_portfolio_names_tax_lot_portfolio_tracking 2>/dev/null || echo "My Portfolio" > /tmp/initial_portfolio_names_tax_lot_portfolio_tracking
echo "0" > /tmp/initial_tax_lots_buy_count
ls "$JSTOCK_DIR/watchlist/" > /tmp/initial_watchlist_names_tax_lot_portfolio_tracking 2>/dev/null || echo "My Watchlist" > /tmp/initial_watchlist_names_tax_lot_portfolio_tracking

echo "Portfolio state:"
echo "  Existing: My Portfolio (SPY only)"
echo "  Removed: Tax Lots 2024 portfolio, Tax Watch 2024 watchlist"
echo "  Agent must: create Tax Lots 2024, enter 5 lots with clearing fees, sell COST, set META/AMZN alerts"

# Launch JStock
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_tax_lot.log 2>&1 &"
sleep 10

# Dismiss news dialog
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize window
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a JStock" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_start_tax_lot.png" 2>/dev/null || true

echo "=== tax_lot_portfolio_tracking setup complete ==="
exit 0
