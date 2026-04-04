#!/bin/bash
echo "=== Setting up record_bond_investment task ==="

source /workspace/scripts/task_utils.sh

# Mark task start
mark_task_start

# Clean up leftover files
clean_portfolio_data "bond_portfolio.xml"

# Create initial portfolio file
# Contains:
# - Client settings
# - One Cash Account "Bond Account" with 15k deposit
# - One Portfolio "Bond Depot" (empty)
# - No securities
cat > /home/ga/Documents/PortfolioData/bond_portfolio.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>USD</baseCurrency>
  <securities/>
  <watchlists/>
  <accounts>
    <account>
      <uuid>acct-bond-001</uuid>
      <name>Bond Account</name>
      <currencyCode>USD</currencyCode>
      <isRetired>false</isRetired>
      <transactions>
        <account-transaction>
          <uuid>txn-dep-bond-001</uuid>
          <date>2024-01-02T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>1500000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
          <note>Initial Funding</note>
        </account-transaction>
      </transactions>
    </account>
  </accounts>
  <portfolios>
    <portfolio>
      <uuid>pf-bond-001</uuid>
      <name>Bond Depot</name>
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

chown ga:ga /home/ga/Documents/PortfolioData/bond_portfolio.xml

# Kill any existing PP instances
pkill -f PortfolioPerformance 2>/dev/null || true
sleep 2

# Launch Portfolio Performance
echo "Launching Portfolio Performance..."
su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"

# Wait for window
wait_for_pp_window 60

# Maximize
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
open_file_in_pp /home/ga/Documents/PortfolioData/bond_portfolio.xml 15

sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="