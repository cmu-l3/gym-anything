#!/bin/bash
echo "=== Setting up create_portfolio_with_transaction task ==="

# Record task start time for anti-gaming (file timestamp checks)
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance to ensure clean start
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# ============================================================
# DATA PREPARATION
# ============================================================
# JStock stores portfolios in ~/.jstock/1.0.7/UnitedState/portfolios/
# We must ensure "My Portfolio" exists (default) and "Retirement Fund" does NOT.

JSTOCK_BASE="/home/ga/.jstock/1.0.7/UnitedState/portfolios"
DEFAULT_PORTFOLIO="$JSTOCK_BASE/My Portfolio"
TARGET_PORTFOLIO="$JSTOCK_BASE/Retirement Fund"

# 1. Clean up target if it exists from previous run
if [ -d "$TARGET_PORTFOLIO" ]; then
    echo "Removing stale target portfolio..."
    rm -rf "$TARGET_PORTFOLIO"
fi

# 2. Reset Default Portfolio to known state
echo "Resetting default portfolio..."
mkdir -p "$DEFAULT_PORTFOLIO"

# Create a valid buyportfolio.csv for My Portfolio (Base State)
# Contains AAPL, MSFT, NVDA
cat > "$DEFAULT_PORTFOLIO/buyportfolio.csv" << 'EOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
EOF

# Create required empty companion files
echo '"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"' > "$DEFAULT_PORTFOLIO/sellportfolio.csv"
echo '"Date","Amount","Comment"' > "$DEFAULT_PORTFOLIO/depositsummary.csv"
echo '"Code","Symbol","Date","Amount","Comment"' > "$DEFAULT_PORTFOLIO/dividendsummary.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock

# ============================================================
# APP LAUNCH
# ============================================================
echo "Launching JStock..."
# Use the launcher script created in env setup
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock.log 2>&1 &"

# Wait for JStock window
echo "Waiting for JStock window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done

# Wait for initialization
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss "JStock News" dialog if it appears (Enter key)
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Ensure focus
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup complete ==="