#!/bin/bash
set -e
echo "=== Setting up record_portfolio_deposits task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

JSTOCK_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_DIR="${JSTOCK_DIR}/portfolios/My Portfolio"
DEPOSIT_FILE="${PORTFOLIO_DIR}/depositsummary.csv"

# Kill any existing JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# Ensure the portfolio directory exists
mkdir -p "$PORTFOLIO_DIR"

# 1. Reset depositsummary.csv to clean state (Header only)
# This removes any previous attempts or stale data
cat > "$DEPOSIT_FILE" << 'CSVEOF'
"Date","Amount","Comment"
CSVEOF

# Record initial state of depositsummary for comparison
cp "$DEPOSIT_FILE" /tmp/initial_depositsummary.csv
# Count lines (should be 1 for header)
wc -l < "$DEPOSIT_FILE" > /tmp/initial_deposit_lines.txt

# 2. Ensure buyportfolio.csv exists with data
# If this is missing, the Portfolio tab might look empty or behave differently
if [ ! -f "${PORTFOLIO_DIR}/buyportfolio.csv" ] || [ $(wc -l < "${PORTFOLIO_DIR}/buyportfolio.csv") -lt 2 ]; then
    cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF
fi

# Set permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

# 3. Launch JStock
echo "Starting JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"
sleep 25

# Dismiss startup dialogs (News, etc.)
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# Maximize JStock window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png" 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Initial deposit lines: $(cat /tmp/initial_deposit_lines.txt)"