#!/bin/bash
set -e
echo "=== Setting up migrate_stock_position task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# ============================================================
# Define Paths
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIOS_DIR="${JSTOCK_DATA_DIR}/portfolios"
OLD_PORTFOLIO_DIR="${PORTFOLIOS_DIR}/My Portfolio"
NEW_PORTFOLIO_DIR="${PORTFOLIOS_DIR}/Semiconductor Fund"

# ============================================================
# Clean State
# ============================================================
# Remove the target portfolio if it exists from previous runs
if [ -d "$NEW_PORTFOLIO_DIR" ]; then
    echo "Removing existing Semiconductor Fund..."
    rm -rf "$NEW_PORTFOLIO_DIR"
fi

# Reset 'My Portfolio' to known starting state
mkdir -p "$OLD_PORTFOLIO_DIR"

# Create the starting buyportfolio.csv with AAPL, MSFT, and NVDA
# NVDA details: Feb 01, 2024 | 25.0 Units | 615.3 Price
cat > "${OLD_PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF

# Ensure other required files exist for My Portfolio
touch "${OLD_PORTFOLIO_DIR}/sellportfolio.csv"
touch "${OLD_PORTFOLIO_DIR}/depositsummary.csv"
touch "${OLD_PORTFOLIO_DIR}/dividendsummary.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock

echo "State reset: My Portfolio contains AAPL, MSFT, NVDA. Semiconductor Fund does not exist."

# ============================================================
# Launch Application
# ============================================================
echo "Starting JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock to stabilize
sleep 20

# Attempt to dismiss news dialog if it appears
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2

# Maximize window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Ensure we are on the Portfolio tab (approx coordinates, or just let agent find it)
# We won't force click here to allow agent to demonstrate navigation, 
# but we ensure the app is focused.
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "JStock" 2>/dev/null || true

# Capture initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="