#!/bin/bash
set -e
echo "=== Setting up rename_portfolio task ==="

# Kill any running JStock instance to ensure clean state
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# ============================================================
# DATA PREPARATION
# ============================================================
# Paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIOS_DIR="${JSTOCK_DATA_DIR}/portfolios"
OLD_PORTFOLIO_DIR="${PORTFOLIOS_DIR}/My Portfolio"
NEW_PORTFOLIO_DIR="${PORTFOLIOS_DIR}/Tech Growth Fund"

# Clean up any artifacts from previous runs
rm -rf "$NEW_PORTFOLIO_DIR"

# Ensure the starting portfolio exists with specific data
mkdir -p "$OLD_PORTFOLIO_DIR"

# Create the buy transactions CSV (AAPL, MSFT, NVDA)
cat > "${OLD_PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF

# Create required companion files (empty but necessary for JStock)
cat > "${OLD_PORTFOLIO_DIR}/sellportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
CSVEOF

cat > "${OLD_PORTFOLIO_DIR}/depositsummary.csv" << 'CSVEOF'
"Date","Amount","Comment"
CSVEOF

cat > "${OLD_PORTFOLIO_DIR}/dividendsummary.csv" << 'CSVEOF'
"Code","Symbol","Date","Amount","Comment"
CSVEOF

# Fix permissions
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock

echo "Prepared 'My Portfolio' with 3 transactions."

# ============================================================
# LAUNCH JSTOCK
# ============================================================
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock window
echo "Waiting for JStock to initialize..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -q "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done

# Allow extra time for Java GUI to fully render and show the News dialog
sleep 15

# Dismiss "JStock News" dialog (Enter usually works to click OK)
echo "Dismissing startup dialogs..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
# Fallback escape
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize the main window
echo "Maximizing window..."
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Ensure window is focused
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a "JStock" 2>/dev/null || true

# Capture initial state
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="