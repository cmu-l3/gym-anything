#!/bin/bash
echo "=== Setting up import_historical_quotes task ==="

source /workspace/scripts/task_utils.sh

# Mark task start
mark_task_start

# Clean up leftover files from other tasks (keep CSV for import)
clean_portfolio_data "investment_portfolio.xml"

# Ensure data files are in place
mkdir -p /home/ga/Documents/PortfolioData
cp /workspace/data/aapl_historical_quotes.csv /home/ga/Documents/PortfolioData/
chown -R ga:ga /home/ga/Documents/PortfolioData

# Create a portfolio with Apple Inc security (no price data yet)
cat > /home/ga/Documents/PortfolioData/investment_portfolio.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>USD</baseCurrency>
  <securities>
    <security>
      <uuid>sec-aapl-import</uuid>
      <name>Apple Inc</name>
      <currencyCode>USD</currencyCode>
      <tickerSymbol>AAPL</tickerSymbol>
      <isin>US0378331005</isin>
      <prices/>
      <attributes/>
      <events/>
      <isRetired>false</isRetired>
    </security>
  </securities>
  <watchlists/>
  <accounts>
    <account>
      <uuid>acct-cash-import</uuid>
      <name>Brokerage (USD)</name>
      <currencyCode>USD</currencyCode>
      <isRetired>false</isRetired>
      <transactions/>
    </account>
  </accounts>
  <portfolios>
    <portfolio>
      <uuid>pf-import-001</uuid>
      <name>Brokerage</name>
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

chown ga:ga /home/ga/Documents/PortfolioData/investment_portfolio.xml

# Record initial price count in the XML
INITIAL_PRICE_COUNT=$(grep -c '<price ' /home/ga/Documents/PortfolioData/investment_portfolio.xml 2>/dev/null || true)
[ -z "$INITIAL_PRICE_COUNT" ] && INITIAL_PRICE_COUNT="0"
printf '%s' "$INITIAL_PRICE_COUNT" > /tmp/initial_price_count

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
open_file_in_pp /home/ga/Documents/PortfolioData/investment_portfolio.xml 15

sleep 2

echo "Initial price count: $INITIAL_PRICE_COUNT"
echo "=== Task setup complete ==="
