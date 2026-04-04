#!/bin/bash
set -e
echo "=== Setting up export_portfolio_to_csv task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/portfolio_export.csv
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 2. Ensure JStock isn't running
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# 3. Pre-populate Portfolio Data (Critical for the task)
# JStock data location for "United States"
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"

mkdir -p "$PORTFOLIO_DIR"

# Write buyportfolio.csv with AAPL, MSFT, NVDA
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF

# Create required companion files to prevent errors
touch "${PORTFOLIO_DIR}/sellportfolio.csv"
touch "${PORTFOLIO_DIR}/depositsummary.csv"
touch "${PORTFOLIO_DIR}/dividendsummary.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock

echo "Portfolio data prepared with AAPL, MSFT, NVDA."

# 4. Launch JStock
echo "Starting JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# 5. Wait for window and handle dialogs
echo "Waiting for JStock window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock" > /dev/null; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done

sleep 5

# Dismiss startup "JStock News" dialog if it appears
# Press Enter (OK) or Escape
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="