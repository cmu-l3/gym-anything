#!/bin/bash
echo "=== Setting up create_savings_plan task ==="

source /workspace/scripts/task_utils.sh

# Mark task start
mark_task_start

# Clean up leftover files from other tasks
clean_portfolio_data "savings_plan.xml"

# Create a portfolio with the specific ETF but no plans
# This XML uses the standard structure for PP
cat > /home/ga/Documents/PortfolioData/savings_plan.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>EUR</baseCurrency>
  <securities>
    <security>
      <uuid>sec-vanguard-world</uuid>
      <name>Vanguard FTSE All-World UCITS ETF</name>
      <currencyCode>EUR</currencyCode>
      <tickerSymbol>VWRL</tickerSymbol>
      <isin>IE00B3RBWM25</isin>
      <prices>
        <price t="2024-01-02" v="10500"/>
        <price t="2024-02-01" v="10800"/>
        <price t="2024-03-01" v="11000"/>
      </prices>
      <attributes/>
      <events/>
      <isRetired>false</isRetired>
    </security>
  </securities>
  <watchlists/>
  <accounts>
    <account>
      <uuid>acct-ref-eur</uuid>
      <name>Reference Account (EUR)</name>
      <currencyCode>EUR</currencyCode>
      <isRetired>false</isRetired>
      <transactions/>
    </account>
  </accounts>
  <portfolios>
    <portfolio>
      <uuid>pf-depot-001</uuid>
      <name>My Depot</name>
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

chown ga:ga /home/ga/Documents/PortfolioData/savings_plan.xml

# Kill any existing PP and relaunch fresh
pkill -f PortfolioPerformance 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"

# Wait for PP to start
sleep 10
wait_for_pp_window 60

# Maximize
WID=$(wmctrl -l | grep -i "Portfolio\|unnamed" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    wmctrl -ia "$WID" 2>/dev/null || true
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any dialogs
sleep 2
xdotool key Escape 2>/dev/null || true
sleep 1

# Open the portfolio file via Ctrl+O (PP ignores file arguments)
open_file_in_pp /home/ga/Documents/PortfolioData/savings_plan.xml 15

sleep 2

echo "=== Task setup complete ==="