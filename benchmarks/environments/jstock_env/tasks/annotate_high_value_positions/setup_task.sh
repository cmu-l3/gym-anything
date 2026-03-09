#!/bin/bash
echo "=== Setting up annotate_high_value_positions task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance to ensure clean setup
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# ============================================================
# Prepare Portfolio Data
# JStock Data Location: ~/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"

mkdir -p "$PORTFOLIO_DIR"
mkdir -p "$WATCHLIST_DIR"

# Ensure Watchlist exists (dependencies)
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Create Portfolio with specific values
# AAPL: 100 * 185.2 = 18520.0 (> 16000) -> TARGET
# MSFT: 50 * 374.5 = 18725.0 (> 16000) -> TARGET
# NVDA: 25 * 615.3 = 15382.5 (< 16000) -> NON-TARGET
echo "Creating buyportfolio.csv with specific values..."
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF

# Create other required files
touch "${PORTFOLIO_DIR}/sellportfolio.csv"
echo '"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"' > "${PORTFOLIO_DIR}/sellportfolio.csv"
echo '"Date","Amount","Comment"' > "${PORTFOLIO_DIR}/depositsummary.csv"
echo '"Code","Symbol","Date","Amount","Comment"' > "${PORTFOLIO_DIR}/dividendsummary.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock

# ============================================================
# Launch Application
# ============================================================
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock to start
for i in {1..40}; do
    if pgrep -f "jstock.jar" > /dev/null; then
        echo "JStock process detected."
        break
    fi
    sleep 1
done
sleep 20 # Wait for GUI

# Dismiss JStock News dialog
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Navigate to Portfolio Management Tab
# Coordinate click (approximate for 1920x1080) to ensure tab is active
echo "Clicking Portfolio Management tab..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 735 158 click 1" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="