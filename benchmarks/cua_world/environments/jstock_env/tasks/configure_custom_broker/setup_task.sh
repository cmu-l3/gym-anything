#!/bin/bash
echo "=== Setting up configure_custom_broker task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# ============================================================
# Prepare JStock Data
# We need to ensure:
# 1. No existing "NeoTrade" broker profile (clean state)
# 2. MSFT is available in the system so the user can type it easily
# ============================================================

JSTOCK_DIR="/home/ga/.jstock/1.0.7"
COUNTRY_DIR="${JSTOCK_DIR}/UnitedState"
WATCHLIST_DIR="${COUNTRY_DIR}/watchlist/My Watchlist"
PORTFOLIO_DIR="${COUNTRY_DIR}/portfolios/My Portfolio"

# Ensure directories exist
mkdir -p "$WATCHLIST_DIR"
mkdir -p "$PORTFOLIO_DIR"

# 1. Clean up any previous "NeoTrade" configuration
# JStock usually stores options in config files. We'll try to sed them out if they exist,
# but primarily we rely on the agent creating it new.
# A simple way to ensure clean slate for specific strings is to delete config files 
# if we wanted a factory reset, but we want to keep the stock data.
# We will just grep to see if it exists and warn, but usually a fresh container or 
# previous cleanup handles this.

# 2. Pre-populate Watchlist with MSFT (and others)
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"MSFT","Microsoft Corp.","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AAPL","Apple Inc.","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# 3. Initialize empty/basic Portfolio
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
CSVEOF

# Ensure other required files exist
touch "${PORTFOLIO_DIR}/sellportfolio.csv"
touch "${PORTFOLIO_DIR}/depositsummary.csv"
touch "${PORTFOLIO_DIR}/dividendsummary.csv"

# Fix permissions
chown -R ga:ga /home/ga/.jstock
chmod -R 755 /home/ga/.jstock

# ============================================================
# Launch JStock
# ============================================================
echo "Launching JStock..."
if ! pgrep -f "jstock.jar" > /dev/null; then
    su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock.log 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "JStock"; then
            echo "JStock window detected"
            break
        fi
        sleep 1
    done
fi

# Maximize and Focus
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Dismiss news dialog if it appears (Enter key)
sleep 5
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="