#!/bin/bash
set -e

echo "=== Setting up JStock environment ==="

# Wait for desktop to be ready
sleep 5

# ============================================================
# Verify JStock is installed
# ============================================================
if [ ! -f /opt/jstock/jstock.sh ] && [ ! -f /opt/jstock/jstock.jar ]; then
    echo "ERROR: JStock not found in /opt/jstock/"
    ls -la /opt/jstock/ 2>/dev/null || echo "/opt/jstock/ does not exist"
    exit 1
fi

echo "JStock installation verified:"
ls -la /opt/jstock/*.sh /opt/jstock/*.jar 2>/dev/null || true

# ============================================================
# Create launcher script for JStock
# CRITICAL: Use /run/user/1000/gdm/Xauthority
#           (not ~/.Xauthority which is 0 bytes in this base image)
# ============================================================
cat > /usr/local/bin/launch-jstock << 'EOF'
#!/bin/bash
export DISPLAY=:1
export XAUTHORITY=/run/user/1000/gdm/Xauthority
cd /opt/jstock
exec /opt/jstock/jstock.sh "$@"
EOF
chmod +x /usr/local/bin/launch-jstock

echo "Created /usr/local/bin/launch-jstock"

# ============================================================
# Pre-create JStock data directories with real US stock data
#
# CRITICAL PATHS (verified by running JStock and inspecting filesystem):
#   Country dir: UnitedState  (Java enum for "United States" — no space)
#   Watchlist:   ~/.jstock/1.0.7/UnitedState/watchlist/My Watchlist/realtimestock.csv
#   Portfolio:   ~/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv
#
# Pre-populate watchlist with real US companies:
#   AAPL  (Apple Inc.)
#   MSFT  (Microsoft Corp.)
#   GOOGL (Alphabet Inc.)
#   AMZN  (Amazon.com Inc.)
#   NVDA  (NVIDIA Corp.)
# ============================================================
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"

mkdir -p "$WATCHLIST_DIR"
mkdir -p "$PORTFOLIO_DIR"

echo "Pre-creating JStock watchlist with real US stocks..."

# Watchlist CSV format (verified from running JStock interactively):
#   - First line must be "timestamp=0"
#   - All values are double-quoted
#   - 17 columns: market data + Fall Below/Rise Above alert thresholds
#   - Prices start as 0.0 (fetched live from Yahoo Finance when online)
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GOOGL","GOOGL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AMZN","AMZN","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

echo "Watchlist CSV created:"
cat "${WATCHLIST_DIR}/realtimestock.csv"

# Portfolio buy transactions CSV format (verified from running JStock interactively):
#   - All values are double-quoted
#   - 18 columns
#   - Date format: "MMM dd, yyyy" (e.g., "Jan 15, 2024")
#   - Units as float: "100.0"
#   - Current Price is "0.0" (fetched live); Gain/Loss shows -100% when offline
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF

echo "Portfolio buy transactions created:"
cat "${PORTFOLIO_DIR}/buyportfolio.csv"

# Create empty companion portfolio files (JStock expects these)
cat > "${PORTFOLIO_DIR}/sellportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
CSVEOF

cat > "${PORTFOLIO_DIR}/depositsummary.csv" << 'CSVEOF'
"Date","Amount","Comment"
CSVEOF

cat > "${PORTFOLIO_DIR}/dividendsummary.csv" << 'CSVEOF'
"Code","Symbol","Date","Amount","Comment"
CSVEOF

# Set correct ownership
chown -R ga:ga /home/ga/.jstock
chmod -R 644 /home/ga/.jstock/
find /home/ga/.jstock -type d -exec chmod 755 {} \;

echo "JStock data directories prepared"

# ============================================================
# Warm-up launch: start JStock to initialize config/state,
# dismiss the JStock News dialog, then close gracefully.
# ============================================================
echo "Performing JStock warm-up launch..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_warmup.log 2>&1 &"

# JStock is a Java app, takes 20-30s to fully load
echo "Waiting for JStock to start (30 seconds)..."
sleep 30

# Check if JStock is running
if pgrep -f "jstock.jar" > /dev/null 2>&1; then
    echo "JStock is running"

    # List visible windows
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null || true

    # Dismiss JStock News dialog (appears on every launch showing version info)
    # Press Enter to click the OK/Continue button
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
    sleep 2

    # Press Escape as fallback
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 2

    # Take a screenshot for debugging
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/jstock_warmup_screen.png" 2>/dev/null || \
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/jstock_warmup_screen.png 2>/dev/null || true
    echo "Warmup screenshot saved to /tmp/jstock_warmup_screen.png"

    # Allow JStock to fully initialize
    sleep 10

    # Close JStock gracefully so it saves its config
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key alt+F4" 2>/dev/null || true
    sleep 2

    # If a save-on-exit dialog appears, press Enter to confirm
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
    sleep 8

    # Force kill if still running
    pkill -f "jstock.jar" 2>/dev/null || true
    sleep 3

    echo "JStock warm-up complete"
else
    echo "WARNING: JStock did not start during warm-up"
    cat /tmp/jstock_warmup.log 2>/dev/null | tail -30 || true
fi

# ============================================================
# Re-apply pre-populated data after warm-up
# (JStock may have written its own state files during warmup)
# ============================================================
echo "Re-applying pre-populated watchlist data..."

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

mkdir -p "$PORTFOLIO_DIR"
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF

# Preserve companion files
cat > "${PORTFOLIO_DIR}/sellportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
CSVEOF

chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

echo "Pre-populated data re-applied"

# ============================================================
# Verify setup
# ============================================================
echo ""
echo "=== JStock Setup Summary ==="
echo "JStock binary: /opt/jstock/jstock.sh"
echo "Data directory: /home/ga/.jstock/1.0.7/"
echo "Watchlist: ${WATCHLIST_DIR}/realtimestock.csv"
echo "Portfolio: ${PORTFOLIO_DIR}/buyportfolio.csv"
echo ""
find /home/ga/.jstock -type f | head -20 || true

echo "=== JStock setup complete ==="
