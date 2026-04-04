#!/bin/bash
set -e

echo "=== Setting up dividend_income_portfolio task ==="

# Kill any running JStock instance
pkill -f "jstock" 2>/dev/null || true
sleep 2

# Record task start timestamp
rm -f /tmp/task_start_ts_dividend_income_portfolio
TS=$(date +%s)
echo "$TS" > /tmp/task_start_ts_dividend_income_portfolio
echo "Task start timestamp: $TS"

JSTOCK_DIR="/home/ga/.jstock/1.0.7/UnitedState"

# Remove any pre-existing "Income Portfolio" (anti-gaming)
rm -rf "$JSTOCK_DIR/portfolios/Income Portfolio" 2>/dev/null || true

# Ensure "My Portfolio" exists as a baseline (agent must create a NEW portfolio)
mkdir -p "$JSTOCK_DIR/portfolios/My Portfolio"
cat > "$JSTOCK_DIR/portfolios/My Portfolio/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"BND","Vanguard Total Bond","Jan 2, 2024","200.0","73.50","0.0","14700.0","0.0","-73.50","-14700.0","-100.0","0.0","0.0","0.0","14700.0","-14700.0","-100.0","existing bond allocation"
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
"T","AT&T Inc.","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"VZ","Verizon Communications","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"KO","Coca-Cola Co.","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"O","Realty Income Corp.","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Set permissions
chown -R ga:ga /home/ga/.jstock 2>/dev/null || true
find /home/ga/.jstock -type f -exec chmod 644 {} \; 2>/dev/null || true
find /home/ga/.jstock -type d -exec chmod 755 {} \; 2>/dev/null || true

# Record initial state (anti-gaming baseline)
ls "$JSTOCK_DIR/portfolios/" > /tmp/initial_portfolio_names_dividend_income_portfolio 2>/dev/null || echo "My Portfolio" > /tmp/initial_portfolio_names_dividend_income_portfolio
echo "0" > /tmp/initial_income_portfolio_buy_count
ls "$JSTOCK_DIR/watchlist/" > /tmp/initial_watchlist_names_dividend_income_portfolio 2>/dev/null || echo "My Watchlist" > /tmp/initial_watchlist_names_dividend_income_portfolio

echo "Portfolio state:"
echo "  Existing: My Portfolio (BND 200 shares)"
echo "  Removed: Income Portfolio"
echo "  Agent must: create Income Portfolio, add T/VZ/KO/O buys with comments, add dividends"

# Launch JStock
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_dividend_income.log 2>&1 &"
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

su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_start_dividend_income.png" 2>/dev/null || true

echo "=== dividend_income_portfolio setup complete ==="
exit 0
