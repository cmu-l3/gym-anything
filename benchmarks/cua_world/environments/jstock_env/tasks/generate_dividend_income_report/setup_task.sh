#!/bin/bash
set -e
echo "=== Setting up Generate Dividend Income Report task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance to ensure clean state
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# Define paths
JSTOCK_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_DIR="${JSTOCK_DIR}/portfolios/My Portfolio"
WATCHLIST_DIR="${JSTOCK_DIR}/watchlist/My Watchlist"
DIVIDEND_FILE="${PORTFOLIO_DIR}/dividendsummary.csv"

# Ensure directories exist
mkdir -p "$PORTFOLIO_DIR"
mkdir -p "$WATCHLIST_DIR"
mkdir -p "/home/ga/Documents"

# 1. Setup Watchlist (Standard US stocks)
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"JNJ","JNJ","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"O","O","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# 2. Inject specific dividend data
# Total Sum should be: 45.0 + 22.5 + 30.0 + 12.75 = 110.25
cat > "$DIVIDEND_FILE" << 'CSVEOF'
"Code","Symbol","Date","Amount","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","45.0","Q1 Dividend"
"MSFT","Microsoft Corp.","Mar 14, 2024","22.5","Q1 Dividend"
"JNJ","Johnson & Johnson","Mar 05, 2024","30.0","Quarterly Div"
"O","Realty Income","Feb 15, 2024","12.75","Monthly Div"
CSVEOF

# Create other required empty portfolio files to prevent errors
touch "${PORTFOLIO_DIR}/buyportfolio.csv"
touch "${PORTFOLIO_DIR}/sellportfolio.csv"
touch "${PORTFOLIO_DIR}/depositsummary.csv"

# Set permissions
chown -R ga:ga "/home/ga/.jstock"
chown -R ga:ga "/home/ga/Documents"
chmod 644 "$DIVIDEND_FILE"

# Clean up any previous result
rm -f /home/ga/Documents/dividend_total.txt

# Start JStock
echo "Starting JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /dev/null 2>&1 &"

# Wait for window
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
sleep 2
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Dismiss news dialog if it appears (Enter key)
sleep 2
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true

# Navigate to Portfolio tab (approximate coordinates or keyboard shortcut)
# Usually Ctrl+2 or clicking the tab. Since coordinates vary, we rely on the agent to navigate,
# but we ensure the window is focused.

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="