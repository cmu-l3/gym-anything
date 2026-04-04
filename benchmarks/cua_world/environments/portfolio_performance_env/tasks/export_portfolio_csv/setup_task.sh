#!/bin/bash
echo "=== Setting up export_portfolio_csv task ==="

source /workspace/scripts/task_utils.sh

# Mark task start
mark_task_start

# Clean up leftover files from other tasks
clean_portfolio_data "diversified_portfolio.xml"

# Create a portfolio with multiple account transactions for a rich export
# Only account-transactions (DEPOSIT, REMOVAL, INTEREST) - no portfolio-transactions
# The task is to export account transactions to CSV
cat > /home/ga/Documents/PortfolioData/diversified_portfolio.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>USD</baseCurrency>
  <securities/>
  <watchlists/>
  <accounts>
    <account>
      <uuid>acct-cash-export</uuid>
      <name>Main Brokerage (USD)</name>
      <currencyCode>USD</currencyCode>
      <isRetired>false</isRetired>
      <transactions>
        <account-transaction>
          <uuid>txn-dep-export-001</uuid>
          <date>2024-01-02T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>5000000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
          <note>Initial funding</note>
        </account-transaction>
        <account-transaction>
          <uuid>txn-dep-export-002</uuid>
          <date>2024-03-01T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>2500000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
          <note>Monthly contribution</note>
        </account-transaction>
        <account-transaction>
          <uuid>txn-interest-001</uuid>
          <date>2024-04-15T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>15000</amount>
          <shares>0</shares>
          <type>INTEREST</type>
          <note>Quarterly interest</note>
        </account-transaction>
        <account-transaction>
          <uuid>txn-dep-export-004</uuid>
          <date>2024-06-01T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>1000000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
          <note>Quarterly contribution</note>
        </account-transaction>
        <account-transaction>
          <uuid>txn-removal-001</uuid>
          <date>2024-06-15T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>500000</amount>
          <shares>0</shares>
          <type>REMOVAL</type>
          <note>Emergency withdrawal</note>
        </account-transaction>
      </transactions>
    </account>
  </accounts>
  <portfolios>
    <portfolio>
      <uuid>pf-export-001</uuid>
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

chown ga:ga /home/ga/Documents/PortfolioData/diversified_portfolio.xml

# Record initial state - no export files yet
printf '%s' "0" > /tmp/initial_csv_count

# Kill any existing PP and relaunch fresh
pkill -f PortfolioPerformance 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"

sleep 10
wait_for_pp_window 60

WID=$(wmctrl -l | grep -i "Portfolio\|unnamed" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    wmctrl -ia "$WID" 2>/dev/null || true
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
xdotool key Escape 2>/dev/null || true
sleep 1

# Open the portfolio file via Ctrl+O (PP ignores file arguments)
open_file_in_pp /home/ga/Documents/PortfolioData/diversified_portfolio.xml 15

sleep 2

echo "=== Task setup complete ==="
