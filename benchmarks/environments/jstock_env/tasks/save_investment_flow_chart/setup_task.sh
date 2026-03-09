#!/bin/bash
set -e
echo "=== Setting up save_investment_flow_chart task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Kill any running JStock instance
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# Define JStock data paths (JStock 1.0.7 uses 'UnitedState' enum name)
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"
DOCS_DIR="/home/ga/Documents"

# Create directories
mkdir -p "$PORTFOLIO_DIR"
mkdir -p "$WATCHLIST_DIR"
mkdir -p "$DOCS_DIR"

# Clean up any previous run artifacts
rm -f "$DOCS_DIR/investment_flow.png"

# ============================================================
# Prepare Data for Investment Flow Chart
# The chart plots "Invested Capital" (Deposits) vs "Current Value" (Portfolio)
# ============================================================

# 1. Populate Deposit Summary (Invested Capital line)
# Format: "Date","Amount","Comment"
cat > "${PORTFOLIO_DIR}/depositsummary.csv" << 'CSVEOF'
"Jan 01, 2024","10000.0","Initial Capital"
"Feb 15, 2024","5000.0","Q1 Contribution"
CSVEOF

# 2. Populate Buy Portfolio (Basis for Current Value)
# 100 Shares of AAPL bought at $100.0 on Jan 02
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 02, 2024","100.0","100.0","0.0","10000.0","0.0","0.0","0.0","0.0","0.0","0.0","0.0","10000.0","0.0","0.0",""
CSVEOF

# 3. Populate Watchlist with "Last" price (Determines Current Value)
# AAPL Price set to 180.0 (Profit -> Current Value line will be above Invested Capital)
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","175.0","178.0","180.0","182.0","177.0","500000","5.0","2.8","0","180.0","100","180.1","200","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# Ensure empty companion files exist to prevent errors
touch "${PORTFOLIO_DIR}/sellportfolio.csv"
touch "${PORTFOLIO_DIR}/dividendsummary.csv"

# Set permissions
chown -R ga:ga /home/ga/.jstock
chown -R ga:ga /home/ga/Documents
chmod -R 755 /home/ga/.jstock

# ============================================================
# Launch JStock
# ============================================================
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for window to appear
echo "Waiting for JStock window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done

# Maximize window (Crucial for VLM visibility)
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss "JStock News" dialog (Press Enter)
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Ensure focus
DISPLAY=:1 wmctrl -a "JStock" 2>/dev/null || true

# Take initial screenshot for verification
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="