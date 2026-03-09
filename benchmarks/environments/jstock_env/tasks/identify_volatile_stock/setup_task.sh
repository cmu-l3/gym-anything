#!/bin/bash
set -e
echo "=== Setting up identify_volatile_stock task ==="

# 1. Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# 2. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 3. Clean up previous results
rm -f /home/ga/most_volatile_stock.txt

# 4. Prepare JStock Data Directory
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"

mkdir -p "$WATCHLIST_DIR"

# 5. Inject specific market data for the task
# Data designed so AMD is the winner (~5.07% volatility)
# Format: Code,Symbol,Prev,Open,Last,High,Low,Vol,Chg,Chg(%),...
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AMD","AMD","0.0","0.0","178.29","178.63","169.58","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"TSLA","TSLA","0.0","0.0","207.83","212.73","203.88","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","613.62","628.49","609.31","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AAPL","AAPL","0.0","0.0","195.50","196.38","194.34","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","402.56","405.63","399.75","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Fix permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

echo "Injected stock data for AMD, TSLA, NVDA, AAPL, MSFT"

# 6. Launch JStock
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# 7. Wait for JStock to start
echo "Waiting for JStock to start (30 seconds)..."
sleep 30

# 8. Dismiss JStock News dialog (appears on every launch)
# Try pressing Enter
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 2
# Try pressing Escape as fallback
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# 9. Maximize window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 10. Ensure Watchlist tab is active (it's the default, but click to be sure)
# Coordinates approx middle-left
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 300 300 click 1" 2>/dev/null || true

# 11. Capture initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="