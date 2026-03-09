#!/bin/bash
set -e
echo "=== Setting up record_acquisition_buyout_event task ==="

# 1. Kill any running JStock instance to ensure clean file writing
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# 2. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Prepare JStock Data Directories
# Note: JStock uses "UnitedState" (singular) as the enum name for US market
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"

mkdir -p "$PORTFOLIO_DIR"
mkdir -p "$WATCHLIST_DIR"

# 4. Pre-populate Buy Portfolio with the ATVI position
# We include standard holdings (AAPL, MSFT) plus the target ATVI holding
# ATVI: 50 shares bought at $75.50 on Jan 03, 2023
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"ATVI","Activision Blizzard","Jan 03, 2023","50.0","75.5","0.0","3775.0","0.0","-75.5","-3775.0","-100.0","0.0","0.0","0.0","3775.0","-3775.0","-100.0","Legacy holding"
CSVEOF

# 5. Reset Sell Portfolio (Start Empty)
# Agent must create the entry here
cat > "${PORTFOLIO_DIR}/sellportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
CSVEOF

# 6. Ensure Watchlist exists (standard hygiene)
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"ATVI","ATVI","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# 7. Set Permissions
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock

# 8. Launch JStock
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# 9. Wait for application to stabilize
echo "Waiting for window..."
sleep 20

# 10. Dismiss "JStock News" dialog if it appears
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# 11. Maximize and Focus
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "JStock" 2>/dev/null || true

# 12. Navigate to Portfolio Tab (to help the agent start in right context)
# Click coordinate approx (735, 158) for Portfolio tab
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 735 158 click 1" 2>/dev/null || true
sleep 2

# 13. Capture Initial Screenshot
echo "Capturing initial state..."
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="