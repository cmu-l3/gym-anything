#!/bin/bash
echo "=== Setting up record_short_sale_trade task ==="

source /workspace/scripts/task_utils.sh

# Mark task start for anti-gaming
mark_task_start

# Clean up any previous portfolio data and ensure directory exists
clean_portfolio_data "margin_account.xml"
mkdir -p /home/ga/Documents/PortfolioData

# Create the initial portfolio file
# Includes one Cash Account ($25k) and one Securities Account (Depot)
# No securities or portfolio transactions yet
cat > /home/ga/Documents/PortfolioData/margin_account.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>USD</baseCurrency>
  <securities/>
  <watchlists/>
  <accounts>
    <account>
      <uuid>UUID-CASH-MARGIN-1</uuid>
      <name>Margin Cash</name>
      <currencyCode>USD</currencyCode>
      <isRetired>false</isRetired>
      <transactions>
        <account-transaction>
          <uuid>UUID-DEP-INIT-1</uuid>
          <date>2021-01-01T00:00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>2500000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
          <note>Initial Margin Funding</note>
        </account-transaction>
      </transactions>
    </account>
  </accounts>
  <portfolios>
    <portfolio>
      <uuid>UUID-DEPOT-MARGIN-1</uuid>
      <name>Margin Depot</name>
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

# Set ownership
chown ga:ga /home/ga/Documents/PortfolioData/margin_account.xml

# Kill any existing PP instance
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

# Dismiss welcome/update dialogs if any
sleep 3
xdotool key Escape 2>/dev/null || true
sleep 1

# Open the specific portfolio file
open_file_in_pp /home/ga/Documents/PortfolioData/margin_account.xml 15

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="