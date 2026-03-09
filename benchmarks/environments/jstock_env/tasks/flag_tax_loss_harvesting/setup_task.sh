#!/bin/bash
set -e
echo "=== Setting up 'Flag Tax Loss Harvesting' task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# Define paths
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_DIR="$JSTOCK_DATA_DIR/portfolios/Semiconductors"
WATCHLIST_DIR="$JSTOCK_DATA_DIR/watchlist/Semiconductors"

# Clean up any previous run
rm -rf "$PORTFOLIO_DIR"
rm -rf "$WATCHLIST_DIR"

mkdir -p "$PORTFOLIO_DIR"
mkdir -p "$WATCHLIST_DIR"

# ============================================================
# Create Portfolio Data
# Scenario:
# - NVDA: Huge winner (+100%)
# - AMD: Moderate winner (+10%)
# - TSM: Moderate loser (-16.6%)
# - INTC: Big loser (-50%) -> TARGET
#
# We pre-calculate the values in the CSV so they appear immediately 
# even if JStock is offline or hasn't fetched new prices yet.
# ============================================================

cat > "$PORTFOLIO_DIR/buyportfolio.csv" << 'EOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"NVDA","NVIDIA Corp.","Jan 15, 2024","10.0","400.0","800.0","4000.0","8000.0","400.0","4000.0","100.0","0.0","0.0","0.0","4000.0","4000.0","100.0",""
"AMD","Adv Micro Dev","Jan 15, 2024","20.0","100.0","110.0","2000.0","2200.0","10.0","200.0","10.0","0.0","0.0","0.0","2000.0","200.0","10.0",""
"INTC","Intel Corp.","Jan 15, 2024","100.0","50.0","25.0","5000.0","2500.0","-25.0","-2500.0","-50.0","0.0","0.0","0.0","5000.0","-2500.0","-50.0",""
"TSM","Taiwan Semi","Jan 15, 2024","30.0","120.0","100.0","3600.0","3000.0","-20.0","-600.0","-16.6","0.0","0.0","0.0","3600.0","-600.0","-16.6",""
EOF

# Create required companion files for the portfolio to load correctly
touch "$PORTFOLIO_DIR/sellportfolio.csv"
touch "$PORTFOLIO_DIR/depositsummary.csv"
touch "$PORTFOLIO_DIR/dividendsummary.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock

echo "Portfolio data created at $PORTFOLIO_DIR"

# ============================================================
# Launch JStock
# ============================================================
echo "Launching JStock..."
if ! pgrep -f "jstock.jar" > /dev/null; then
    su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"
fi

# Wait for window
echo "Waiting for JStock window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss "JStock News" dialog if it appears (Enter key)
sleep 2
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Capture initial state
echo "Capturing initial screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="