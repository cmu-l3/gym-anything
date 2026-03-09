#!/bin/bash
echo "=== Setting up record_mortgage_payment task ==="

source /workspace/scripts/task_utils.sh

# Mark task start
mark_task_start

# Clean up leftover files
clean_portfolio_data "NetWorthPortfolio.xml"

# Create the portfolio file with Checking and Mortgage accounts
# Note: PP stores amounts in cents (e.g., 1500000 = $15,000.00)
# Negative balance for liability
cat > /home/ga/Documents/PortfolioData/NetWorthPortfolio.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>USD</baseCurrency>
  <securities/>
  <watchlists/>
  <accounts>
    <account>
      <uuid>acct-checking-001</uuid>
      <name>Checking Account</name>
      <currencyCode>USD</currencyCode>
      <isRetired>false</isRetired>
      <transactions>
        <account-transaction>
          <uuid>txn-init-checking</uuid>
          <date>2024-05-01T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>1500000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
          <note>Starting Balance</note>
        </account-transaction>
      </transactions>
    </account>
    <account>
      <uuid>acct-mortgage-001</uuid>
      <name>Mortgage Loan</name>
      <currencyCode>USD</currencyCode>
      <isRetired>false</isRetired>
      <transactions>
        <account-transaction>
          <uuid>txn-init-mortgage</uuid>
          <date>2024-01-01T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>-34500000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
          <note>Initial Loan Balance</note>
        </account-transaction>
      </transactions>
    </account>
  </accounts>
  <portfolios/>
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

chown ga:ga /home/ga/Documents/PortfolioData/NetWorthPortfolio.xml

# Ensure Portfolio Performance is running
pkill -f PortfolioPerformance 2>/dev/null || true
sleep 2

echo "Launching Portfolio Performance..."
su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"

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
open_file_in_pp /home/ga/Documents/PortfolioData/NetWorthPortfolio.xml 15

sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="