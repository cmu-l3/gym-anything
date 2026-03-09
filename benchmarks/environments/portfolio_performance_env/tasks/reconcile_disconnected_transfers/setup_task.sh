#!/bin/bash
echo "=== Setting up reconcile_disconnected_transfers task ==="

source /workspace/scripts/task_utils.sh

# Mark task start time
mark_task_start

# Define file path
PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/disconnected_transfers.xml"

# Clean up previous data
clean_portfolio_data "disconnected_transfers.xml"

# Create the portfolio file with UNLINKED transactions (Removals/Deposits)
# Amounts are in cents (factor 100)
# $2,500.00 -> 250000
# $1,200.00 -> 120000

cat > "$PORTFOLIO_FILE" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>USD</baseCurrency>
  <securities/>
  <watchlists/>
  <accounts>
    <account>
      <uuid>acct-checking</uuid>
      <name>Main Checking</name>
      <currencyCode>USD</currencyCode>
      <isRetired>false</isRetired>
      <transactions>
        <account-transaction>
          <uuid>txn-rem-001</uuid>
          <date>2024-05-15T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>250000</amount>
          <shares>0</shares>
          <type>REMOVAL</type>
          <note>Transfer to Brokerage (Unlinked)</note>
        </account-transaction>
        <account-transaction>
          <uuid>txn-rem-002</uuid>
          <date>2024-05-28T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>120000</amount>
          <shares>0</shares>
          <type>REMOVAL</type>
          <note>Transfer to Brokerage (Unlinked)</note>
        </account-transaction>
      </transactions>
    </account>
    <account>
      <uuid>acct-brokerage</uuid>
      <name>Brokerage Cash</name>
      <currencyCode>USD</currencyCode>
      <isRetired>false</isRetired>
      <transactions>
        <account-transaction>
          <uuid>txn-dep-001</uuid>
          <date>2024-05-15T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>250000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
          <note>Transfer from Checking (Unlinked)</note>
        </account-transaction>
        <account-transaction>
          <uuid>txn-dep-002</uuid>
          <date>2024-05-28T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>120000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
          <note>Transfer from Checking (Unlinked)</note>
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

# Set ownership
chown ga:ga "$PORTFOLIO_FILE"

# Kill any existing PP instance
pkill -f PortfolioPerformance 2>/dev/null || true
sleep 2

# Launch PP
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
open_file_in_pp "$PORTFOLIO_FILE" 15

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="