#!/bin/bash
echo "=== Setting up add_security_and_buy task ==="

source /workspace/scripts/task_utils.sh

# Mark task start
mark_task_start

# Clean up leftover files from other tasks
clean_portfolio_data "growth_portfolio.xml"

# Create a portfolio with Apple Inc only (no portfolio-transactions)
# Agent needs to add GOOGL security and record a BUY transaction
cat > /home/ga/Documents/PortfolioData/growth_portfolio.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>USD</baseCurrency>
  <securities>
    <security>
      <uuid>sec-aapl-growth</uuid>
      <name>Apple Inc</name>
      <currencyCode>USD</currencyCode>
      <tickerSymbol>AAPL</tickerSymbol>
      <isin>US0378331005</isin>
      <prices>
        <price t="2024-01-02" v="18564"/>
        <price t="2024-02-01" v="18686"/>
        <price t="2024-03-01" v="17966"/>
        <price t="2024-04-01" v="17148"/>
        <price t="2024-05-01" v="16930"/>
        <price t="2024-06-01" v="19403"/>
      </prices>
      <attributes/>
      <events/>
      <isRetired>false</isRetired>
    </security>
  </securities>
  <watchlists/>
  <accounts>
    <account>
      <uuid>acct-cash-growth</uuid>
      <name>Main Brokerage (USD)</name>
      <currencyCode>USD</currencyCode>
      <isRetired>false</isRetired>
      <transactions>
        <account-transaction>
          <uuid>txn-dep-growth-001</uuid>
          <date>2024-01-02T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>15000000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
        </account-transaction>
      </transactions>
    </account>
  </accounts>
  <portfolios>
    <portfolio>
      <uuid>pf-growth-001</uuid>
      <name>Main Brokerage</name>
      <isRetired>false</isRetired>
      <referenceAccount reference="../../../accounts/account"/>
      <transactions/>
    </portfolio>
  </portfolios>
  <plans/>
  <taxonomies/>
  <dashboards/>
  <properties/>
  <settings>
    <bookmarks/>
    <attributeTypes/>
    <configurationSets/>
  </settings>
</client>
XMLEOF

chown ga:ga /home/ga/Documents/PortfolioData/growth_portfolio.xml

# Record initial state
INITIAL_SEC_COUNT=$(python3 -c "
import xml.etree.ElementTree as ET
try:
    root = ET.parse('/home/ga/Documents/PortfolioData/growth_portfolio.xml').getroot()
    se = root.find('securities')
    print(len(se.findall('security')) if se is not None else 0)
except: print(0)
" 2>/dev/null || true)
[ -z "$INITIAL_SEC_COUNT" ] && INITIAL_SEC_COUNT="0"
INITIAL_TXN_COUNT=$(grep -c '<portfolio-transaction>' /home/ga/Documents/PortfolioData/growth_portfolio.xml 2>/dev/null || true)
[ -z "$INITIAL_TXN_COUNT" ] && INITIAL_TXN_COUNT="0"
printf '%s' "$INITIAL_SEC_COUNT" > /tmp/initial_sec_count
printf '%s' "$INITIAL_TXN_COUNT" > /tmp/initial_txn_count

# Kill any existing PP and relaunch fresh
pkill -f PortfolioPerformance 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"

sleep 10
wait_for_pp_window 60

# Maximize
WID=$(wmctrl -l | grep -i "Portfolio\|unnamed" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    wmctrl -ia "$WID" 2>/dev/null || true
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
xdotool key Escape 2>/dev/null || true
sleep 1

# Open the portfolio file via Ctrl+O (PP ignores file arguments)
open_file_in_pp /home/ga/Documents/PortfolioData/growth_portfolio.xml 15

sleep 2

echo "Initial securities: $INITIAL_SEC_COUNT, transactions: $INITIAL_TXN_COUNT"
echo "=== Task setup complete ==="
