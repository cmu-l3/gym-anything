#!/bin/bash
set -e
echo "=== Setting up delete_portfolio task ==="

# 1. Kill any running JStock instance to ensure clean data setup
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# 2. Define Paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_ROOT="${JSTOCK_DATA_DIR}/portfolios"

# 3. Prepare "My Portfolio" (The one to keep)
PRESERVED_DIR="${PORTFOLIO_ROOT}/My Portfolio"
mkdir -p "$PRESERVED_DIR"

# Populating My Portfolio with AAPL, MSFT, NVDA
cat > "${PRESERVED_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF

# Create required empty companion files for My Portfolio
echo '"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"' > "${PRESERVED_DIR}/sellportfolio.csv"
echo '"Date","Amount","Comment"' > "${PRESERVED_DIR}/depositsummary.csv"
echo '"Code","Symbol","Date","Amount","Comment"' > "${PRESERVED_DIR}/dividendsummary.csv"

# 4. Prepare "Speculative Trades" (The one to delete)
TARGET_DIR="${PORTFOLIO_ROOT}/Speculative Trades"
mkdir -p "$TARGET_DIR"

# Populating Speculative Trades with META, AMD
cat > "${TARGET_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"META","Meta Platforms","Mar 01, 2024","20.0","475.5","0.0","9510.0","0.0","-475.5","-9510.0","-100.0","0.0","0.0","0.0","9510.0","-9510.0","-100.0",""
"AMD","Advanced Micro Devices","Mar 05, 2024","40.0","162.3","0.0","6492.0","0.0","-162.3","-6492.0","-100.0","0.0","0.0","0.0","6492.0","-6492.0","-100.0",""
CSVEOF

# Create required empty companion files for Speculative Trades
echo '"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"' > "${TARGET_DIR}/sellportfolio.csv"
echo '"Date","Amount","Comment"' > "${TARGET_DIR}/depositsummary.csv"
echo '"Code","Symbol","Date","Amount","Comment"' > "${TARGET_DIR}/dividendsummary.csv"

# 5. Set Permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

# 6. Record Initial State
date +%s > /tmp/task_start_time.txt
ls -1 "${PORTFOLIO_ROOT}" | wc -l > /tmp/initial_portfolio_count.txt
echo "Initial portfolios created: $(ls "${PORTFOLIO_ROOT}")"

# 7. Launch JStock
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock to start (Java apps are slow)
echo "Waiting for JStock to initialize (30s)..."
sleep 30

# 8. Handle Dialogs & UI Setup
# Dismiss News Dialog (Enter)
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
# Dismiss any potential second dialog (Escape)
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize Window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Switch to Portfolio Tab
# JStock usually starts on Watchlist. Portfolio tab is the second tab.
# We'll click the location of the Portfolio tab (approx x=735, y=158 based on 1080p layout analysis)
# Or use keyboard shortcut if available (Ctrl+2 often works in Java tabbed panes, but JStock uses custom UI).
# Let's use mouse click to be safe.
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 735 158 click 1" 2>/dev/null || true
sleep 2

# 9. Initial Screenshot
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png" 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="