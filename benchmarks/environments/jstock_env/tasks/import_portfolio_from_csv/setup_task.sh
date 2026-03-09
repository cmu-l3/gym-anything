#!/bin/bash
set -e
echo "=== Setting up import_portfolio_from_csv task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Prepare the Import CSV file
IMPORT_DIR="/home/ga/Documents"
mkdir -p "$IMPORT_DIR"

# JStock CSV format for portfolio import
cat > "${IMPORT_DIR}/import_portfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"TSLA","Tesla Inc.","Mar 15, 2024","30.0","171.5","0.0","5145.0","0.0","-171.5","-5145.0","-100.0","0.0","0.0","0.0","5145.0","-5145.0","-100.0",""
"META","Meta Platforms Inc.","Feb 20, 2024","40.0","473.25","0.0","18930.0","0.0","-473.25","-18930.0","-100.0","0.0","0.0","0.0","18930.0","-18930.0","-100.0",""
"JPM","JPMorgan Chase & Co.","Jan 10, 2024","60.0","172.8","0.0","10368.0","0.0","-172.8","-10368.0","-100.0","0.0","0.0","0.0","10368.0","-10368.0","-100.0",""
"V","Visa Inc.","Dec 15, 2023","20.0","260.15","0.0","5203.0","0.0","-260.15","-5203.0","-100.0","0.0","0.0","0.0","5203.0","-5203.0","-100.0",""
"JNJ","Johnson & Johnson","Nov 20, 2023","45.0","148.9","0.0","6700.5","0.0","-148.9","-6700.5","-100.0","0.0","0.0","0.0","6700.5","-6700.5","-100.0",""
CSVEOF

chown ga:ga "${IMPORT_DIR}/import_portfolio.csv"
chmod 644 "${IMPORT_DIR}/import_portfolio.csv"
echo "Created import file at ${IMPORT_DIR}/import_portfolio.csv"

# 3. Ensure clean start for JStock
pkill -f "jstock" 2>/dev/null || true
sleep 2

# 4. Launch JStock
echo "Launching JStock..."
# Using setsid to detach from shell, redirect output to avoid hanging
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# 5. Wait for JStock window
echo "Waiting for JStock window..."
for i in {1..60}; do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i -E "jstock|stock"; then
        echo "JStock window detected at iteration $i"
        break
    fi
    sleep 1
done
# Give it a moment to fully render
sleep 10

# 6. Handle startup dialogs (News/Welcome)
# Press Enter to dismiss "JStock News" or similar default dialogs
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
# Press Escape just in case
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 1

# 7. Maximize window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 8. Record initial portfolio state (for diffing later)
PORTFOLIO_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"
if [ -f "$PORTFOLIO_FILE" ]; then
    cp "$PORTFOLIO_FILE" /tmp/initial_buyportfolio.csv
else
    echo "" > /tmp/initial_buyportfolio.csv
fi

# 9. Take initial screenshot
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial_state.png" 2>/dev/null || \
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_initial_state.png" 2>/dev/null || true

echo "=== Setup complete ==="