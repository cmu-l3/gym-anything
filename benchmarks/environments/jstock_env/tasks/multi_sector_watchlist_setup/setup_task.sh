#!/bin/bash
set -e

echo "=== Setting up multi_sector_watchlist_setup task ==="

# Kill any running JStock instance
pkill -f "jstock" 2>/dev/null || true
sleep 2

# Record task start timestamp
rm -f /tmp/task_start_ts_multi_sector_watchlist_setup
TS=$(date +%s)
echo "$TS" > /tmp/task_start_ts_multi_sector_watchlist_setup
echo "Task start timestamp: $TS"

JSTOCK_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_BASE="$JSTOCK_DIR/watchlist"

# Remove any pre-existing sector watchlists (anti-gaming)
rm -rf "$WATCHLIST_BASE/Technology_Coverage" 2>/dev/null || true
rm -rf "$WATCHLIST_BASE/Healthcare_Coverage" 2>/dev/null || true
rm -rf "$WATCHLIST_BASE/Energy_Coverage" 2>/dev/null || true

# Ensure "My Watchlist" exists with a few neutral stocks
mkdir -p "$WATCHLIST_BASE/My Watchlist"
cat > "$WATCHLIST_BASE/My Watchlist/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"SPY","SPY","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AGG","AGG","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Ensure baseline portfolio exists
mkdir -p "$JSTOCK_DIR/portfolios/My Portfolio"
cat > "$JSTOCK_DIR/portfolios/My Portfolio/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
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

# Set permissions
chown -R ga:ga /home/ga/.jstock 2>/dev/null || true
find /home/ga/.jstock -type f -exec chmod 644 {} \; 2>/dev/null || true
find /home/ga/.jstock -type d -exec chmod 755 {} \; 2>/dev/null || true

# Record initial state (anti-gaming baseline)
ls "$WATCHLIST_BASE/" > /tmp/initial_watchlist_names_multi_sector_watchlist_setup 2>/dev/null || echo "My Watchlist" > /tmp/initial_watchlist_names_multi_sector_watchlist_setup
echo "0" > /tmp/initial_sector_watchlist_count_multi_sector_watchlist_setup

echo "Watchlist state:"
echo "  Existing: My Watchlist (SPY, AGG)"
echo "  Removed: Technology_Coverage, Healthcare_Coverage, Energy_Coverage"

# Launch JStock
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_multi_sector.log 2>&1 &"
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

su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_start_multi_sector.png" 2>/dev/null || true

echo "=== multi_sector_watchlist_setup setup complete ==="
exit 0
