#!/bin/bash
echo "=== Setting up import_csv_transactions task ==="

source /workspace/scripts/task_utils.sh

# Mark task start time
mark_task_start

# Ensure data directory exists
mkdir -p /home/ga/Documents/PortfolioData

# 1. Create the CSV file
cat > /home/ga/Documents/PortfolioData/broker_transactions.csv << 'CSVEOF'
Date,Type,ISIN,Security Name,Shares,Value,Fees,Note
2024-01-15,Buy,US0378331005,Apple Inc,10,1855.90,9.99,Initial AAPL position
2024-02-01,Buy,US5949181045,Microsoft Corp,5,1987.90,9.99,MSFT purchase
2024-02-15,Buy,US0231351067,Amazon.com Inc,20,3407.00,9.99,AMZN purchase
2024-03-01,Buy,US02079K3059,Alphabet Inc,15,2071.05,9.99,GOOGL purchase
2024-03-15,Buy,US88160R1014,Tesla Inc,8,1308.56,9.99,TSLA purchase
2024-04-01,Sell,US0378331005,Apple Inc,3,510.09,9.99,Partial AAPL sell
2024-04-15,Buy,US0231351067,Amazon.com Inc,10,1861.30,9.99,Additional AMZN
2024-05-01,Sell,US02079K3059,Alphabet Inc,5,872.95,9.99,Partial GOOGL sell
CSVEOF

# 2. Create the Portfolio XML file
# Pre-populated with securities and accounts, but NO transactions
cat > /home/ga/Documents/PortfolioData/us_tech_portfolio.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>USD</baseCurrency>
  <securities>
    <security>
      <uuid>sec-aapl-001</uuid>
      <name>Apple Inc</name>
      <currencyCode>USD</currencyCode>
      <tickerSymbol>AAPL</tickerSymbol>
      <isin>US0378331005</isin>
      <prices/>
      <isRetired>false</isRetired>
    </security>
    <security>
      <uuid>sec-msft-001</uuid>
      <name>Microsoft Corp</name>
      <currencyCode>USD</currencyCode>
      <tickerSymbol>MSFT</tickerSymbol>
      <isin>US5949181045</isin>
      <prices/>
      <isRetired>false</isRetired>
    </security>
    <security>
      <uuid>sec-amzn-001</uuid>
      <name>Amazon.com Inc</name>
      <currencyCode>USD</currencyCode>
      <tickerSymbol>AMZN</tickerSymbol>
      <isin>US0231351067</isin>
      <prices/>
      <isRetired>false</isRetired>
    </security>
    <security>
      <uuid>sec-googl-001</uuid>
      <name>Alphabet Inc</name>
      <currencyCode>USD</currencyCode>
      <tickerSymbol>GOOGL</tickerSymbol>
      <isin>US02079K3059</isin>
      <prices/>
      <isRetired>false</isRetired>
    </security>
    <security>
      <uuid>sec-tsla-001</uuid>
      <name>Tesla Inc</name>
      <currencyCode>USD</currencyCode>
      <tickerSymbol>TSLA</tickerSymbol>
      <isin>US88160R1014</isin>
      <prices/>
      <isRetired>false</isRetired>
    </security>
  </securities>
  <watchlists/>
  <accounts>
    <account>
      <uuid>acct-cash-001</uuid>
      <name>USD Cash Account</name>
      <currencyCode>USD</currencyCode>
      <isRetired>false</isRetired>
      <transactions>
        <account-transaction>
          <uuid>txn-init-dep</uuid>
          <date>2024-01-01T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>5000000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
          <note>Starting Capital</note>
        </account-transaction>
      </transactions>
    </account>
  </accounts>
  <portfolios>
    <portfolio>
      <uuid>pf-brokerage-001</uuid>
      <name>Brokerage Account</name>
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

# Set permissions
chown ga:ga /home/ga/Documents/PortfolioData/broker_transactions.csv
chown ga:ga /home/ga/Documents/PortfolioData/us_tech_portfolio.xml

# 3. Launch Portfolio Performance
# Kill any existing instance
pkill -f PortfolioPerformance 2>/dev/null || true
sleep 2

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

# Dismiss welcome dialogs
sleep 3
xdotool key Escape 2>/dev/null || true
sleep 1

# 4. Open the specific portfolio file
open_file_in_pp /home/ga/Documents/PortfolioData/us_tech_portfolio.xml 15

# Record initial state: 0 portfolio transactions
echo "0" > /tmp/initial_txn_count

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="