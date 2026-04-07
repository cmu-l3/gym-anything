#!/bin/bash
set -e

echo "=== Setting up quarterly_portfolio_rebalance task ==="

# ============================================================
# 1. Kill any running JStock instance
# ============================================================
pkill -f "jstock" 2>/dev/null || true
sleep 2

# ============================================================
# 2. Delete stale outputs BEFORE recording timestamp
# ============================================================
rm -f /home/ga/Documents/portfolio_q1_export.csv 2>/dev/null || true
rm -f /tmp/quarterly_portfolio_rebalance_result.json 2>/dev/null || true
rm -f /tmp/task_start_fund_rebalance.png 2>/dev/null || true

# ============================================================
# 3. Record task start timestamp (anti-gaming)
# ============================================================
TS=$(date +%s)
echo "$TS" > /tmp/task_start_ts_quarterly_portfolio_rebalance
echo "Task start timestamp: $TS"

# ============================================================
# 4. Configure JStock data directories
# ============================================================
JSTOCK_DIR="/home/ga/.jstock/1.0.7/UnitedState"
PORTFOLIO_DIR="$JSTOCK_DIR/portfolios/My Portfolio"
WATCHLIST_DIR="$JSTOCK_DIR/watchlist/My Watchlist"

mkdir -p "$PORTFOLIO_DIR"
mkdir -p "$WATCHLIST_DIR"

# Remove any pre-existing task-specific watchlist (anti-gaming)
rm -rf "$JSTOCK_DIR/watchlist/Q1 Rebalance Watch" 2>/dev/null || true

# ============================================================
# 5. Pre-populate buy portfolio (4 existing positions)
# ============================================================
cat > "$PORTFOLIO_DIR/buyportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Purchase Price","Current Price","Purchase Value","Current Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Purchase Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
"AAPL","Apple Inc.","Jan 02, 2024","150.0","185.5","0.0","27825.0","0.0","-185.5","-27825.0","-100.0","0.0","0.0","0.0","27825.0","-27825.0","-100.0",""
"MSFT","Microsoft Corp.","Jan 02, 2024","80.0","420.0","0.0","33600.0","0.0","-420.0","-33600.0","-100.0","0.0","0.0","0.0","33600.0","-33600.0","-100.0",""
"NVDA","NVIDIA Corp.","Jan 15, 2024","35.0","615.0","0.0","21525.0","0.0","-615.0","-21525.0","-100.0","0.0","0.0","0.0","21525.0","-21525.0","-100.0",""
"JNJ","Johnson & Johnson","Jan 15, 2024","40.0","160.0","0.0","6400.0","0.0","-160.0","-6400.0","-100.0","0.0","0.0","0.0","6400.0","-6400.0","-100.0",""
CSVEOF

# ============================================================
# 6. Reset sell portfolio (empty — agent must add sell entries)
# ============================================================
cat > "$PORTFOLIO_DIR/sellportfolio.csv" << 'CSVEOF'
"Code","Symbol","Date","Units","Selling Price","Purchase Price","Selling Value","Purchase Value","Gain/Loss Price","Gain/Loss Value","Gain/Loss %","Broker","Clearing Fee","Stamp Duty","Net Selling Value","Net Gain/Loss Value","Net Gain/Loss %","Comment"
CSVEOF

# ============================================================
# 7. Pre-populate deposit summary (existing $100K initial funding)
# ============================================================
cat > "$PORTFOLIO_DIR/depositsummary.csv" << 'CSVEOF'
"Date","Amount","Comment"
"Jan 01, 2024","100000.0","Initial portfolio funding"
CSVEOF

# ============================================================
# 8. Reset dividend summary (empty — agent must add dividend)
# ============================================================
cat > "$PORTFOLIO_DIR/dividendsummary.csv" << 'CSVEOF'
"Code","Symbol","Date","Amount","Comment"
CSVEOF

# ============================================================
# 9. Pre-populate watchlist with existing holdings
# ============================================================
cat > "$WATCHLIST_DIR/realtimestock.csv" << 'CSVEOF'
"timestamp=0"
"Code","Symbol","Prev","Open","Last","High","Low","Vol","Chg","Chg (%)","L.Vol","Buy","B.Qty","Sell","S.Qty","Fall Below","Rise Above"
"AAPL","AAPL","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"MSFT","MSFT","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"NVDA","NVDA","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
"JNJ","JNJ","0.0","0.0","0.0","0.0","0.0","0","0.0","0.0","0","0.0","0","0.0","0","0.0","0.0"
CSVEOF

# ============================================================
# 10. Create the quarterly rebalancing memo document
# ============================================================
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/q1_rebalance_memo.txt << 'MEMOEOF'
QUARTERLY PORTFOLIO REVIEW — Q1 2024

TO: Portfolio Manager
FROM: Investment Committee
DATE: March 1, 2024
RE: Q1 Rebalancing Actions

The committee has approved the following adjustments based on
our quarterly review. Execute all actions within JStock.

CAPITAL ACTIONS:
- Deposit $25,000 on March 1, 2024
  Comment: "Q1 capital contribution"
- Record Apple dividend of $111.00 received March 10, 2024
  Comment: "Q1 2024 dividend"

SELL ORDERS (execute March 15, 2024, broker fee $4.95 each):
- Sell 50 shares of AAPL at $215.00/share
- Sell 15 shares of NVDA at $750.00/share

BUY ORDERS (execute March 15, 2024, broker fee $4.95 each):
Buy the maximum whole shares (round DOWN) for each allocation:
- Energy:     $25,000 into Exxon Mobil (XOM)      at $105.00/share
- Staples:    $20,000 into Coca-Cola (KO)          at $58.00/share
- Healthcare: $12,000 into Johnson & Johnson (JNJ) at $162.50/share

RISK MONITORING:
Create watchlist "Q1 Rebalance Watch" with all six current holdings
(AAPL, MSFT, NVDA, JNJ, XOM, KO). For each stock set:
- Fall Below alert at 5% below its purchase price
- Rise Above alert at 10% above its purchase price
For stocks with multiple buy entries, use the earliest purchase price.
Round all alert values to the nearest cent.

REPORTING:
Export updated buy portfolio to:
/home/ga/Documents/portfolio_q1_export.csv
MEMOEOF

# ============================================================
# 11. Set permissions
# ============================================================
chown -R ga:ga /home/ga/.jstock 2>/dev/null || true
find /home/ga/.jstock -type f -exec chmod 644 {} \; 2>/dev/null || true
find /home/ga/.jstock -type d -exec chmod 755 {} \; 2>/dev/null || true
chown -R ga:ga /home/ga/Documents 2>/dev/null || true

# ============================================================
# 12. Record anti-gaming baselines
# ============================================================
wc -l < "$PORTFOLIO_DIR/buyportfolio.csv" > /tmp/initial_buy_count_quarterly_rebalance 2>/dev/null || echo "0" > /tmp/initial_buy_count_quarterly_rebalance
wc -l < "$PORTFOLIO_DIR/sellportfolio.csv" > /tmp/initial_sell_count_quarterly_rebalance 2>/dev/null || echo "0" > /tmp/initial_sell_count_quarterly_rebalance
wc -l < "$PORTFOLIO_DIR/depositsummary.csv" > /tmp/initial_deposit_count_quarterly_rebalance 2>/dev/null || echo "0" > /tmp/initial_deposit_count_quarterly_rebalance
wc -l < "$PORTFOLIO_DIR/dividendsummary.csv" > /tmp/initial_dividend_count_quarterly_rebalance 2>/dev/null || echo "0" > /tmp/initial_dividend_count_quarterly_rebalance
ls "$JSTOCK_DIR/watchlist/" > /tmp/initial_watchlist_names_quarterly_rebalance 2>/dev/null || true
cp "$PORTFOLIO_DIR/buyportfolio.csv" /tmp/initial_buyportfolio_quarterly_rebalance.csv 2>/dev/null || true
cp "$PORTFOLIO_DIR/sellportfolio.csv" /tmp/initial_sellportfolio_quarterly_rebalance.csv 2>/dev/null || true

echo "State prepared:"
echo "  Portfolio: AAPL(150), MSFT(80), NVDA(35), JNJ(40)"
echo "  Deposit: $100K initial funding"
echo "  Sell portfolio: empty"
echo "  Dividends: empty"
echo "  Watchlist: AAPL, MSFT, NVDA, JNJ"
echo "  Memo: /home/ga/Documents/q1_rebalance_memo.txt"

# ============================================================
# 13. Launch JStock
# ============================================================
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_quarterly_rebalance.log 2>&1 &"

# Wait for JStock window
echo "Waiting for JStock window..."
for i in {1..45}; do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "jstock"; then
        echo "JStock window detected."
        break
    fi
    sleep 1
done
sleep 5

# ============================================================
# 14. Dismiss startup news dialog
# ============================================================
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Return" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape" 2>/dev/null || true
sleep 2

# ============================================================
# 15. Maximize window
# ============================================================
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -a JStock" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz" 2>/dev/null || true
sleep 2

# ============================================================
# 16. Navigate to Portfolio Management tab
# ============================================================
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 735 158 click 1" 2>/dev/null || true
sleep 2

# ============================================================
# 17. Capture initial screenshot
# ============================================================
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_start_fund_rebalance.png" 2>/dev/null || true

echo "=== quarterly_portfolio_rebalance setup complete ==="
exit 0
