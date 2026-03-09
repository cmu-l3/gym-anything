#!/bin/bash
echo "=== Setting up record_outbound_delivery task ==="

source /workspace/scripts/task_utils.sh

# Mark task start
mark_task_start

# Clean up leftover files
clean_portfolio_data "gift_transfer_portfolio.xml"

# Create the specific portfolio file for this task
# Includes AAPL security, Schwab accounts, and an initial BUY of 100 shares
cat > /home/ga/Documents/PortfolioData/gift_transfer_portfolio.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>USD</baseCurrency>
  <securities>
    <security>
      <uuid>sec-aapl-gift</uuid>
      <name>Apple Inc</name>
      <currencyCode>USD</currencyCode>
      <tickerSymbol>AAPL</tickerSymbol>
      <isin>US0378331005</isin>
      <prices>
        <price t="2024-01-15" v="18500"/>
        <price t="2024-12-15" v="24500"/>
      </prices>
      <attributes/>
      <events/>
      <isRetired>false</isRetired>
    </security>
  </securities>
  <watchlists/>
  <accounts>
    <account>
      <uuid>acct-cash-schwab</uuid>
      <name>Schwab Cash Account</name>
      <currencyCode>USD</currencyCode>
      <isRetired>false</isRetired>
      <transactions>
        <account-transaction>
          <uuid>txn-dep-initial</uuid>
          <date>2024-01-01T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>5000000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
          <note>Initial Funding</note>
        </account-transaction>
      </transactions>
    </account>
  </accounts>
  <portfolios>
    <portfolio>
      <uuid>pf-brokerage-schwab</uuid>
      <name>Schwab Brokerage</name>
      <isRetired>false</isRetired>
      <referenceAccount reference="../../../accounts/account"/>
      <transactions>
        <portfolio-transaction>
          <uuid>txn-buy-initial</uuid>
          <date>2024-01-15T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>1850000</amount>
          <shares>10000000000</shares>
          <type>BUY</type>
          <note>Initial Purchase</note>
          <security reference="../../../../../securities/security"/>
        </portfolio-transaction>
      </transactions>
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

chown ga:ga /home/ga/Documents/PortfolioData/gift_transfer_portfolio.xml

# Kill any existing PP instances
pkill -f PortfolioPerformance 2>/dev/null || true
sleep 2

# Launch Portfolio Performance
echo "Launching Portfolio Performance..."
su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"

# Wait for window
wait_for_pp_window 60

# Maximize window
WID=$(wmctrl -l | grep -i "Portfolio\|unnamed" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    wmctrl -ia "$WID" 2>/dev/null || true
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss dialogs
sleep 2
xdotool key Escape 2>/dev/null || true
sleep 1

# Open the file
echo "Opening portfolio file..."
open_file_in_pp /home/ga/Documents/PortfolioData/gift_transfer_portfolio.xml 15

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="