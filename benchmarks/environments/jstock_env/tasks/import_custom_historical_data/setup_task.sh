#!/bin/bash
set -e
echo "=== Setting up import_custom_historical_data task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Clean up previous state
# ============================================================
JSTOCK_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DIR}/watchlist/My Watchlist"
DATABASE_DIR="${JSTOCK_DIR}/database"

# Remove TSLA from watchlist if present (reset to default 5 stocks)
mkdir -p "$WATCHLIST_DIR"
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GOOGL","GOOGL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AMZN","AMZN","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Remove TSLA history from database if present
mkdir -p "$DATABASE_DIR"
rm -f "$DATABASE_DIR/TSLA.zip" "$DATABASE_DIR/TSLA.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock

# ============================================================
# 2. Create the Source CSV File
#    Real TSLA data for Jan 2024
# ============================================================
mkdir -p /home/ga/Documents
cat > "/home/ga/Documents/tsla_history.csv" << 'CSVEOF'
Date,Open,High,Low,Close,Volume
2024-01-02,250.08,251.25,244.41,248.42,104654200
2024-01-03,244.98,245.68,236.32,238.45,121082600
2024-01-04,239.25,242.70,237.73,237.93,102629300
2024-01-05,236.86,240.12,234.90,237.49,92379400
2024-01-08,236.14,241.25,235.30,240.45,85166600
2024-01-09,238.11,238.23,232.04,234.96,96994000
2024-01-10,235.10,235.50,231.29,233.94,91628500
2024-01-11,230.57,230.93,225.37,227.22,105873600
2024-01-12,220.08,225.34,217.15,218.89,122889000
2024-01-16,215.10,223.49,212.18,219.91,115355000
2024-01-17,214.86,215.67,212.01,215.55,103164400
2024-01-18,216.88,217.45,208.74,211.88,108783600
2024-01-19,209.99,213.22,207.56,212.19,102095800
2024-01-22,212.26,217.80,206.27,208.80,117952500
2024-01-23,211.30,215.65,207.75,209.14,106605900
2024-01-24,211.88,212.73,206.77,207.83,130626600
2024-01-25,189.70,193.00,180.06,182.63,198076800
2024-01-26,185.50,186.78,182.10,183.25,107343200
2024-01-29,185.63,191.48,183.67,190.93,125013100
2024-01-30,195.33,196.36,190.61,191.59,109474400
2024-01-31,187.00,193.76,185.85,187.29,110264200
CSVEOF

chown ga:ga /home/ga/Documents/tsla_history.csv

# ============================================================
# 3. Launch JStock
# ============================================================
echo "Starting JStock..."
# Use launcher script from environment setup
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Wait a bit for UI to settle
sleep 5

# Dismiss news dialog if it appears (Enter key)
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="