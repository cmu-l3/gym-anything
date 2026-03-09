#!/bin/bash
set -e
echo "=== Setting up Change Reporting Currency Task ==="

source /workspace/scripts/task_utils.sh

# Mark task start for anti-gaming
mark_task_start

# Ensure directory exists
mkdir -p /home/ga/Documents/PortfolioData
chown -R ga:ga /home/ga/Documents/PortfolioData

# 1. Create the initial USD portfolio XML
# This file has USD as base currency and some US securities
cat > /home/ga/Documents/PortfolioData/us_portfolio.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>60</version>
  <baseCurrency>USD</baseCurrency>
  <securities>
    <security>
      <uuid>sec-aapl-uuid</uuid>
      <name>Apple Inc</name>
      <currencyCode>USD</currencyCode>
      <isin>US0378331005</isin>
      <tickerSymbol>AAPL</tickerSymbol>
      <prices>
        <price t="2024-01-02" v="18500"/>
        <price t="2024-01-15" v="18300"/>
      </prices>
    </security>
    <security>
      <uuid>sec-msft-uuid</uuid>
      <name>Microsoft Corp</name>
      <currencyCode>USD</currencyCode>
      <isin>US5949181045</isin>
      <tickerSymbol>MSFT</tickerSymbol>
      <prices>
        <price t="2024-01-02" v="37000"/>
        <price t="2024-01-15" v="39000"/>
      </prices>
    </security>
  </securities>
  <accounts>
    <account>
      <uuid>acct-cash-uuid</uuid>
      <name>USD Cash</name>
      <currencyCode>USD</currencyCode>
      <transactions>
         <account-transaction>
          <uuid>txn-dep-001</uuid>
          <date>2024-01-02T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>1000000</amount>
          <shares>0</shares>
          <type>DEPOSIT</type>
        </account-transaction>
      </transactions>
    </account>
  </accounts>
  <portfolios>
    <portfolio>
      <uuid>port-main-uuid</uuid>
      <name>Main Depot</name>
      <referenceAccount reference="../../../accounts/account"/>
      <transactions>
        <portfolio-transaction>
          <uuid>txn-buy-aapl</uuid>
          <date>2024-01-02T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>185000</amount>
          <shares>1000000000</shares>
          <type>BUY</type>
          <security reference="../../../../../securities/security"/>
        </portfolio-transaction>
      </transactions>
    </portfolio>
  </portfolios>
</client>
EOF

# 2. Create the Exchange Rate CSV (Real Data Sample - EURUSD)
# Format: Date, Close (Standard Yahoo Finance CSV format)
cat > /home/ga/Documents/PortfolioData/eur_usd_rates.csv << 'EOF'
Date,Close
2024-01-02,0.9142
2024-01-03,0.9158
2024-01-04,0.9135
2024-01-05,0.9138
2024-01-08,0.9132
2024-01-09,0.9145
2024-01-10,0.9112
2024-01-11,0.9108
2024-01-12,0.9130
2024-01-15,0.9134
2024-01-16,0.9195
2024-01-17,0.9202
2024-01-18,0.9198
2024-01-19,0.9185
2024-01-22,0.9180
EOF

# Set permissions
chown ga:ga /home/ga/Documents/PortfolioData/us_portfolio.xml
chown ga:ga /home/ga/Documents/PortfolioData/eur_usd_rates.csv

# 3. Launch Application
# Kill any existing PP
pkill -f "PortfolioPerformance" 2>/dev/null || true
sleep 2

# Launch PP
echo "Launching Portfolio Performance..."
su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"

# Wait for window
wait_for_pp_window 60

# Maximize
WID=$(wmctrl -l | grep -i "Portfolio Performance\|PortfolioPerformance\|unnamed" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    wmctrl -ia "$WID" 2>/dev/null || true
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Open the specific file using hotkeys (PP ignores CLI args for files)
sleep 5
open_file_in_pp "/home/ga/Documents/PortfolioData/us_portfolio.xml"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="