#!/bin/bash
echo "=== Setting up switch_market_country task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance to ensure clean start
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# ============================================================
# CLEAN START STATE
# Remove UnitedKingdom directory if it exists to ensure agent
# actually performs the switch and data creation.
# ============================================================
UK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedKingdom"
if [ -d "$UK_DATA_DIR" ]; then
    echo "Removing existing UK data to force fresh creation..."
    rm -rf "$UK_DATA_DIR"
fi

# Ensure US data exists (so we start in US mode as described)
US_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
mkdir -p "$US_DATA_DIR/watchlist/My Watchlist"

# Reset US watchlist to a known state (optional, but good for consistency)
cat > "$US_DATA_DIR/watchlist/My Watchlist/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Ensure permissions are correct
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock

# ============================================================
# LAUNCH JSTOCK
# ============================================================
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock to start
echo "Waiting for window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected"
        break
    fi
    sleep 1
done
sleep 5

# Dismiss JStock News dialog if it appears
# Press Enter (OK) then Escape just in case
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Maximize window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="