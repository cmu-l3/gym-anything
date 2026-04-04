#!/bin/bash
set -e
echo "=== Setting up Flag Largest Holding task ==="

# Define JStock data paths (UnitedState is the internal enum name)
JSTOCK_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_DIR="${JSTOCK_DIR}/portfolios/My Portfolio"
WATCHLIST_DIR="${JSTOCK_DIR}/watchlist/My Watchlist"

# Create directories
mkdir -p "$PORTFOLIO_DIR"
mkdir -p "$WATCHLIST_DIR"

# 1. Pre-populate Watchlist
# Required for JStock to recognize symbols in the portfolio
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'EOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"T","T","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GOOGL","GOOGL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AMZN","AMZN","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"F","F","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
EOF

# 2. Pre-populate Portfolio with scenario data
# Scenario Data:
# - T:     500 units @ 15.0  = $7,500
# - GOOGL: 20 units  @ 140.0 = $2,800
# - AMZN:  100 units @ 170.0 = $17,000  <-- Target (Largest Value)
# - F:     1000 units @ 12.0 = $12,000  <-- Distractor (Largest Quantity)
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'EOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"T","AT&T Inc.","Jan 10, 2024","500.0","15.0","0.0","7500.0","0.0","-15.0","-7500.0","-100.0","0.0","0.0","0.0","7500.0","-7500.0","-100.0",""
"GOOGL","Alphabet Inc.","Jan 12, 2024","20.0","140.0","0.0","2800.0","0.0","-140.0","-2800.0","-100.0","0.0","0.0","0.0","2800.0","-2800.0","-100.0",""
"AMZN","Amazon.com Inc.","Jan 15, 2024","100.0","170.0","0.0","17000.0","0.0","-170.0","-17000.0","-100.0","0.0","0.0","0.0","17000.0","-17000.0","-100.0",""
"F","Ford Motor Company","Jan 20, 2024","1000.0","12.0","0.0","12000.0","0.0","-12.0","-12000.0","-100.0","0.0","0.0","0.0","12000.0","-12000.0","-100.0",""
EOF

# Create required companion files to prevent JStock errors
touch "${PORTFOLIO_DIR}/sellportfolio.csv"
touch "${PORTFOLIO_DIR}/depositsummary.csv"
touch "${PORTFOLIO_DIR}/dividendsummary.csv"

# Fix permissions
chown -R ga:ga "/home/ga/.jstock"
chmod -R 755 "/home/ga/.jstock"

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Start JStock
if ! pgrep -f "jstock.jar" > /dev/null; then
    echo "Starting JStock..."
    su - ga -c "setsid /usr/local/bin/launch-jstock > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
            echo "JStock window detected."
            break
        fi
        sleep 1
    done
fi

# Ensure window is maximized and focused
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Navigate to Portfolio tab (simulated click as fallback if it doesn't default there)
# Coordinates approx (400, 60) relative to window, or rely on agent finding it.
# We'll leave navigation to the agent as part of the task difficulty.

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="