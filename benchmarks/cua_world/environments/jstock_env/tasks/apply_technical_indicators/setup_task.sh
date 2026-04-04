#!/bin/bash
set -e
echo "=== Setting up apply_technical_indicators task ==="

# 1. Kill any running JStock instance to ensure clean state
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# 2. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 3. Clean up any previous output file
OUTPUT_FILE="/home/ga/Documents/aapl_trend_analysis.png"
rm -f "$OUTPUT_FILE"
echo "Cleaned up $OUTPUT_FILE"

# 4. Ensure JStock data directories exist and AAPL is in the watchlist
# (Using the standard path structure identified in environment setup)
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"
mkdir -p "$WATCHLIST_DIR"

# Ensure AAPL is in the watchlist (re-writing strictly to be safe)
# This format matches the JStock 1.0.7 CSV structure
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Set permissions
chown -R ga:ga /home/ga/.jstock

# 5. Launch JStock
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# 6. Wait for window and handle startup dialogs
echo "Waiting for JStock window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done

# Short sleep to let the window render
sleep 5

# Attempt to dismiss the "JStock News" dialog if it appears
# Pressing 'Return' usually clicks the default "OK" button
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 2
# Fallback: Escape
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# 7. Maximize the window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 8. Focus the window
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# 9. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="