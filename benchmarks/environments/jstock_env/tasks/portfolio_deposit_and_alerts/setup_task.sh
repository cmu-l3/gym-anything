#!/bin/bash
set -e

echo "=== Setting up portfolio_deposit_and_alerts task ==="

# Kill any running JStock instance
pkill -f "jstock" 2>/dev/null || true
sleep 2

# Record task start timestamp
rm -f /tmp/task_start_ts_portfolio_deposit_and_alerts
TS=$(date +%s)
echo "$TS" > /tmp/task_start_ts_portfolio_deposit_and_alerts
echo "Task start timestamp: $TS"

JSTOCK_DIR="/home/ga/.jstock/1.0.7/UnitedState"

# Remove any pre-existing task-specific data (anti-gaming)
rm -rf "$JSTOCK_DIR/portfolios/Fund Alpha" 2>/dev/null || true
rm -rf "$JSTOCK_DIR/watchlist/Fund Alpha Watch" 2>/dev/null || true

# Ensure "My Portfolio" exists as unrelated baseline data
mkdir -p "$JSTOCK_DIR/portfolios/My Portfolio"
cat > "$JSTOCK_DIR/portfolios/My Portfolio/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 2, 2024","50.0","185.64","0.0","9282.0","0.0","-185.64","-9282.0","-100.0","0.0","0.0","0.0","9282.0","-9282.0","-100.0","existing holding"
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

# Ensure baseline watchlist exists with some unrelated stocks
mkdir -p "$JSTOCK_DIR/watchlist/My Watchlist"
cat > "$JSTOCK_DIR/watchlist/My Watchlist/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","Apple Inc.","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","180.0","200.0"
CSVEOF

# Set permissions
chown -R ga:ga /home/ga/.jstock 2>/dev/null || true
find /home/ga/.jstock -type f -exec chmod 644 {} \; 2>/dev/null || true
find /home/ga/.jstock -type d -exec chmod 755 {} \; 2>/dev/null || true

# Record initial state (anti-gaming baseline)
ls "$JSTOCK_DIR/portfolios/" > /tmp/initial_portfolio_names_portfolio_deposit_and_alerts 2>/dev/null || echo "My Portfolio" > /tmp/initial_portfolio_names_portfolio_deposit_and_alerts
echo "0" > /tmp/initial_fund_alpha_deposit_count
ls "$JSTOCK_DIR/watchlist/" > /tmp/initial_watchlist_names_portfolio_deposit_and_alerts 2>/dev/null || echo "My Watchlist" > /tmp/initial_watchlist_names_portfolio_deposit_and_alerts

echo "State prepared:"
echo "  Existing: My Portfolio (AAPL 50 shares), My Watchlist (AAPL)"
echo "  Removed: Fund Alpha portfolio, Fund Alpha Watch watchlist"
echo "  Agent must: create Fund Alpha portfolio, add deposit, buy SPY+BRK.B, create Fund Alpha Watch with 6 alerts"

# Launch JStock
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_fund_alpha.log 2>&1 &"
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

su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_start_fund_alpha.png" 2>/dev/null || true

echo "=== portfolio_deposit_and_alerts setup complete ==="
exit 0
