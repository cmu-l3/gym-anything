#!/bin/bash
echo "=== Setting up snapshot_portfolio_clipboard task ==="

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 3

# Cleanup previous run artifacts
rm -f /home/ga/Documents/portfolio_snapshot.txt
mkdir -p /home/ga/Documents

# ============================================================
# Pre-populate portfolio with SPECIFIC unit counts
# AAPL: 123 units
# MSFT: 45 units
# These specific numbers allow us to verify the agent actually
# copied the current state and didn't just type names.
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"

mkdir -p "$WATCHLIST_DIR"
mkdir -p "$PORTFOLIO_DIR"

# Ensure watchlist has the stocks so they resolve correctly
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Create Portfolio CSV
# Note the specific "Units" values: 123.0 and 45.0
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","123.0","185.0","0.0","22755.0","0.0","-185.0","-22755.0","-100.0","0.0","0.0","0.0","22755.0","-22755.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","45.0","370.0","0.0","16650.0","0.0","-370.0","-16650.0","-100.0","0.0","0.0","0.0","16650.0","-16650.0","-100.0",""
CSVEOF

# Create necessary companion files
echo '"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"' > "${PORTFOLIO_DIR}/sellportfolio.csv"
echo '"Date","Amount","Comment"' > "${PORTFOLIO_DIR}/depositsummary.csv"
echo '"Code","Symbol","Date","Amount","Comment"' > "${PORTFOLIO_DIR}/dividendsummary.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

echo "Portfolio data prepared."

# ============================================================
# Launch JStock
# ============================================================
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for JStock window
echo "Waiting for JStock to start..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock" > /dev/null; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss "JStock News" dialog (Enter to click OK)
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 1
# Just in case, try Escape
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 1

# Navigate to "My Portfolio" tab
# JStock usually starts on Watchlist. 
# We need to click the "Portfolio Management" tab or similar.
# In 1920x1080 default layout, Portfolio tab is roughly at 735, 158.
echo "Switching to Portfolio tab..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 735 158 click 1" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="