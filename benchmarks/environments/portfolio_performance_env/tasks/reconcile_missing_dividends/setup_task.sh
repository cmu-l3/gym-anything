#!/bin/bash
echo "=== Setting up Reconcile Missing Dividends Task ==="

source /workspace/scripts/task_utils.sh

# Mark task start time
mark_task_start

# Ensure data directory exists
DATA_DIR="/home/ga/Documents/PortfolioData"
DOCS_DIR="/home/ga/Documents"
mkdir -p "$DATA_DIR"
mkdir -p "$DOCS_DIR"

# Cleanup previous runs
clean_portfolio_data "dividend_audit.xml"
rm -f "$DOCS_DIR/broker_statement_2023.csv"

# 1. Create the Broker Statement CSV (The Ground Truth)
# JNJ 2023 Dividends:
# Mar 07: $1.13 * 100 = $113.00
# Jun 06: $1.19 * 100 = $119.00
# Sep 05: $1.19 * 100 = $119.00 (Missing in XML)
# Dec 05: $1.19 * 100 = $119.00 (Missing in XML)
# Tax assumed 15%

cat > "$DOCS_DIR/broker_statement_2023.csv" << CSVEOF
Date,Transaction Type,Symbol,Description,Quantity,Price,Gross Amount,Tax,Net Amount,Currency
2023-03-07,Dividend,JNJ,"JOHNSON & JOHNSON COM",100,,113.00,16.95,96.05,USD
2023-06-06,Dividend,JNJ,"JOHNSON & JOHNSON COM",100,,119.00,17.85,101.15,USD
2023-09-05,Dividend,JNJ,"JOHNSON & JOHNSON COM",100,,119.00,17.85,101.15,USD
2023-12-05,Dividend,JNJ,"JOHNSON & JOHNSON COM",100,,119.00,17.85,101.15,USD
CSVEOF

# 2. Create the Portfolio XML (With Missing Data)
# Contains:
# - JNJ Security
# - Buy Transaction (2022)
# - Q1 and Q2 Dividends ONLY
cat > "$DATA_DIR/dividend_audit.xml" << XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>USD</baseCurrency>
  <securities>
    <security>
      <uuid>sec-jnj-audit</uuid>
      <name>Johnson &amp; Johnson</name>
      <currencyCode>USD</currencyCode>
      <tickerSymbol>JNJ</tickerSymbol>
      <isin>US4781601046</isin>
      <prices>
        <price t="2023-01-03" v="17600000000"/>
        <price t="2023-12-29" v="15674000000"/>
      </prices>
    </security>
  </securities>
  <accounts>
    <account>
      <uuid>acct-cash-audit</uuid>
      <name>Brokerage Cash (USD)</name>
      <currencyCode>USD</currencyCode>
      <transactions>
        <!-- Initial Funding -->
        <account-transaction>
          <uuid>txn-dep-001</uuid>
          <date>2022-01-01T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>2000000</amount>
          <type>DEPOSIT</type>
        </account-transaction>
        <!-- Q1 Dividend (Recorded) -->
        <account-transaction>
          <uuid>txn-div-q1</uuid>
          <date>2023-03-07T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>9605</amount>
          <type>DIVIDENDS</type>
          <security reference="../../../../../securities/security"/>
          <units>
             <unit type="GROSS_VALUE">
               <amount currency="USD" amount="11300"/>
             </unit>
             <unit type="TAX">
               <amount currency="USD" amount="1695"/>
             </unit>
          </units>
        </account-transaction>
        <!-- Q2 Dividend (Recorded) -->
        <account-transaction>
          <uuid>txn-div-q2</uuid>
          <date>2023-06-06T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>10115</amount>
          <type>DIVIDENDS</type>
          <security reference="../../../../../securities/security"/>
          <units>
             <unit type="GROSS_VALUE">
               <amount currency="USD" amount="11900"/>
             </unit>
             <unit type="TAX">
               <amount currency="USD" amount="1785"/>
             </unit>
          </units>
        </account-transaction>
      </transactions>
    </account>
  </accounts>
  <portfolios>
    <portfolio>
      <uuid>pf-audit-001</uuid>
      <name>My Portfolio</name>
      <referenceAccount reference="../../../accounts/account"/>
      <transactions>
        <!-- Buy 100 shares in 2022 -->
        <portfolio-transaction>
          <uuid>txn-buy-001</uuid>
          <date>2022-06-15T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>1700000</amount>
          <shares>10000000000</shares>
          <type>BUY</type>
          <security reference="../../../../../securities/security"/>
        </portfolio-transaction>
      </transactions>
    </portfolio>
  </portfolios>
</client>
XMLEOF

# Set permissions
chown ga:ga "$DATA_DIR/dividend_audit.xml"
chown ga:ga "$DOCS_DIR/broker_statement_2023.csv"

# 3. Launch Application
echo "Launching Portfolio Performance..."
pkill -f PortfolioPerformance 2>/dev/null || true
sleep 2

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
sleep 3
xdotool key Escape 2>/dev/null || true
sleep 1

# Open the file
open_file_in_pp "$DATA_DIR/dividend_audit.xml" 15

echo "=== Setup Complete ==="