#!/bin/bash
set -e
echo "=== Setting up segment_tech_holdings task ==="

# 1. Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# 2. Define Data Directories
# JStock stores data in ~/.jstock/1.0.7/UnitedState (enum name, no space)
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_ROOT="${JSTOCK_DATA_DIR}/portfolios"
MY_PORTFOLIO_DIR="${PORTFOLIO_ROOT}/My Portfolio"
TECH_PORTFOLIO_DIR="${PORTFOLIO_ROOT}/Tech Portfolio"

# 3. Clean Slate
# Remove Tech Portfolio if it exists from previous run
if [ -d "$TECH_PORTFOLIO_DIR" ]; then
    echo "Removing existing Tech Portfolio..."
    rm -rf "$TECH_PORTFOLIO_DIR"
fi

# Ensure My Portfolio directory exists
mkdir -p "$MY_PORTFOLIO_DIR"

# 4. Populate 'My Portfolio' with starting data
# Format: Code, Symbol, Date, Units, Purchase Price, ...
echo "Populating My Portfolio with AAPL, MSFT, NVDA..."
cat > "${MY_PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF

# Create required companion files for My Portfolio
touch "${MY_PORTFOLIO_DIR}/sellportfolio.csv"
touch "${MY_PORTFOLIO_DIR}/depositsummary.csv"
touch "${MY_PORTFOLIO_DIR}/dividendsummary.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Launch JStock
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# 7. Wait for window and handle dialogs
echo "Waiting for JStock window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "Window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss "JStock News" dialog if it appears (Enter key)
# It usually appears on startup.
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 1

# Ensure we are on the Portfolio tab (Click coordinate approx 735, 158)
# Or use keyboard shortcut if available (Ctrl+2 usually works for 2nd tab in Java apps, 
# but JStock might not strictly follow this. Clicking is safer if we know resolution)
# We'll rely on the agent to navigate, but we can try to help.
# Default view is often Watchlist.

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="