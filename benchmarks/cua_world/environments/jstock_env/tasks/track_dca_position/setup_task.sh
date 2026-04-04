#!/bin/bash
echo "=== Setting up track_dca_position task ==="

# 1. Kill any running JStock instance to ensure clean state
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# 2. Define Paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios"
DCA_PORTFOLIO_DIR="${PORTFOLIO_DIR}/DCA Strategy"
SUMMARY_FILE="/home/ga/dca_summary.txt"

# 3. Clean up previous run artifacts
if [ -d "$DCA_PORTFOLIO_DIR" ]; then
    echo "Removing existing DCA Strategy portfolio..."
    rm -rf "$DCA_PORTFOLIO_DIR"
fi

if [ -f "$SUMMARY_FILE" ]; then
    echo "Removing existing summary file..."
    rm -f "$SUMMARY_FILE"
fi

# 4. Ensure "My Portfolio" exists (standard state)
DEFAULT_PORTFOLIO="${PORTFOLIO_DIR}/My Portfolio"
mkdir -p "$DEFAULT_PORTFOLIO"
# Pre-populate My Portfolio with some dummy data if missing, so JStock starts normally
if [ ! -f "${DEFAULT_PORTFOLIO}/buyportfolio.csv" ]; then
    echo "Creating default My Portfolio..."
    cat > "${DEFAULT_PORTFOLIO}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
CSVEOF
fi

# Fix permissions
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock

# 5. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# 6. Launch JStock
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock to start (Java app, can be slow)
echo "Waiting for JStock window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done
sleep 5 # Extra buffer for GUI to render

# 7. Dismiss "JStock News" dialog if it appears
# Press Enter to dismiss (default button is usually OK/Close)
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2
# Press Escape as backup
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# 8. Maximize window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# 9. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="