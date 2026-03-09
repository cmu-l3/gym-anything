#!/bin/bash
set -e

echo "=== Setting up Liquidate Portfolio Task ==="

# 1. Kill any running JStock instance to ensure clean file operations
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# 2. Define Data Directories
JSTOCK_DATA_DIR="/home/ga/.jstock/1.0.7/UnitedState"
WATCHLIST_DIR="${JSTOCK_DATA_DIR}/watchlist/My Watchlist"
PORTFOLIO_DIR="${JSTOCK_DATA_DIR}/portfolios/My Portfolio"

mkdir -p "$WATCHLIST_DIR"
mkdir -p "$PORTFOLIO_DIR"

# 3. Pre-populate Watchlist (Required for symbols to be recognized)
cat > "${WATCHLIST_DIR}/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"GOOGL","GOOGL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"AMZN","AMZN","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# 4. Pre-populate Buy Portfolio (The Holdings to be Liquidated)
# Columns: Code, Symbol, Date, Units, Purchase Price, ...
cat > "${PORTFOLIO_DIR}/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 15, 2024","100.0","185.2","0.0","18520.0","0.0","-185.2","-18520.0","-100.0","0.0","0.0","0.0","18520.0","-18520.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 15, 2024","50.0","374.5","0.0","18725.0","0.0","-374.5","-18725.0","-100.0","0.0","0.0","0.0","18725.0","-18725.0","-100.0",""
"NVDA","NVIDIA Corp.","Feb 01, 2024","25.0","615.3","0.0","15382.5","0.0","-615.3","-15382.5","-100.0","0.0","0.0","0.0","15382.5","-15382.5","-100.0",""
CSVEOF

# 5. Create Empty Sell Portfolio (Agent must populate this)
cat > "${PORTFOLIO_DIR}/sellportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
CSVEOF

# 6. Create Companion Files (Required by JStock)
cat > "${PORTFOLIO_DIR}/depositsummary.csv" << 'CSVEOF'
"Date","Amount","Comment"
CSVEOF
cat > "${PORTFOLIO_DIR}/dividendsummary.csv" << 'CSVEOF'
"Code","Symbol","Date","Amount","Comment"
CSVEOF

# 7. Set Permissions
chown -R ga:ga /home/ga/.jstock
find /home/ga/.jstock -type f -exec chmod 644 {} \;
find /home/ga/.jstock -type d -exec chmod 755 {} \;

# 8. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt
# Record initial hash of sellportfolio to detect changes
sha256sum "${PORTFOLIO_DIR}/sellportfolio.csv" > /tmp/initial_sell_hash.txt

# 9. Launch JStock
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# 10. Wait for Window and Initialize
echo "Waiting for JStock to start..."
for i in {1..40}; do
    if wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done
sleep 5 # Wait for splash screen/dialogs

# 11. Handle 'JStock News' Dialog
# Press Return to dismiss news, or Escape as fallback
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# 12. Maximize Window
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 13. Navigate to Portfolio Management Tab
# Click roughly where the Portfolio tab is (Coordinate based on 1080p layout: ~735, 158)
echo "Navigating to Portfolio tab..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 735 158 click 1" 2>/dev/null || true
sleep 2

# 14. Capture Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="