#!/bin/bash
echo "=== Setting up record_corporate_merger_action task ==="

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# Prepare JStock Data
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"

mkdir -p "$WATCHLIST_DIR"
mkdir -p "$PORTFOLIO_DIR"

# 1. Setup Watchlist (Include XLNX and AMD)
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"XLNX","XLNX","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AMD","AMD","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# 2. Setup Portfolio (Only XLNX exists initially)
# Purchase: 100 shares @ $145.00 on Jan 1, 2021
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"XLNX","Xilinx Inc.","Jan 01, 2021","100.0","145.0","0.0","14500.0","0.0","-145.0","-14500.0","-100.0","0.0","0.0","0.0","14500.0","-14500.0","-100.0","Legacy Holding"
CSVEOF

# Empty Sell Portfolio
cat > "${PORTFOLIO_DIR}/sellportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
CSVEOF

# Empty Summary files
cat > "${PORTFOLIO_DIR}/depositsummary.csv" << 'CSVEOF'
"Date","Amount","Comment"
CSVEOF
cat > "${PORTFOLIO_DIR}/dividendsummary.csv" << 'CSVEOF'
"Code","Symbol","Date","Amount","Comment"
CSVEOF

# Set Permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

echo "JStock data prepared with 100 XLNX shares."

# ============================================================
# Launch JStock
# ============================================================
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

echo "Waiting for JStock to start (30 seconds)..."
sleep 30

# Dismiss JStock News dialog
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Click Portfolio Management tab (Approx coordinates, verified in similar tasks)
# If coordinates fail, agent usually finds the tab visually.
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 735 158 click 1" 2>/dev/null || true
sleep 2

# Take initial screenshot
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_start_state.png" 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_start_state.png 2>/dev/null || true

echo "=== Setup complete ==="