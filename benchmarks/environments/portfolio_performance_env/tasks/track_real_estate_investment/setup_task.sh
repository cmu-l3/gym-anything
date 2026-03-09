#!/bin/bash
echo "=== Setting up track_real_estate_investment task ==="

source /workspace/scripts/task_utils.sh

# Mark task start
mark_task_start

# Clean up leftover files
clean_portfolio_data "RealEstatePortfolio.xml"

# Create the starting portfolio XML
# Includes:
# - Base Currency: EUR
# - 1 Deposit Account "Girokonto" with 350k EUR
# - 1 Portfolio "Immobilien-Depot"
# - No securities
cat > /home/ga/Documents/PortfolioData/RealEstatePortfolio.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>EUR</baseCurrency>
  <securities/>
  <watchlists/>
  <accounts>
    <account>
      <uuid>acct-giro-001</uuid>
      <name>Girokonto</name>
      <currencyCode>EUR</currencyCode>
      <isRetired>false</isRetired>
      <transactions>
        <account-transaction>
          <uuid>txn-deposit-001</uuid>
          <date>2024-01-02T00:00</date>
          <currencyCode>EUR</currencyCode>
          <amount>35000000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
          <note>Initial Capital</note>
        </account-transaction>
      </transactions>
    </account>
  </accounts>
  <portfolios>
    <portfolio>
      <uuid>pf-immo-001</uuid>
      <name>Immobilien-Depot</name>
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

chown ga:ga /home/ga/Documents/PortfolioData/RealEstatePortfolio.xml

# Kill any existing PP instance
pkill -f PortfolioPerformance 2>/dev/null || true
sleep 3

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

# Dismiss welcome dialogs
sleep 2
xdotool key Escape 2>/dev/null || true
sleep 1

# Open the specific portfolio file
open_file_in_pp /home/ga/Documents/PortfolioData/RealEstatePortfolio.xml 15

sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="