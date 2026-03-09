#!/bin/bash
echo "=== Setting up correct_misassigned_transactions task ==="

source /workspace/scripts/task_utils.sh

# Mark task start
mark_task_start

# Clean up leftover files
clean_portfolio_data "misassigned_trades.xml"

# Create the portfolio file with misassigned transactions
# All transactions are initially in the "Retirement Savings" portfolio (pf-ret)
# "Speculative Tech" portfolio (pf-spec) is initially empty
cat > /home/ga/Documents/PortfolioData/misassigned_trades.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>USD</baseCurrency>
  <securities>
    <security>
      <uuid>sec-nvda</uuid>
      <name>NVIDIA Corp</name>
      <currencyCode>USD</currencyCode>
      <tickerSymbol>NVDA</tickerSymbol>
      <isin>US67066G1040</isin>
      <isRetired>false</isRetired>
    </security>
    <security>
      <uuid>sec-amd</uuid>
      <name>Advanced Micro Devices</name>
      <currencyCode>USD</currencyCode>
      <tickerSymbol>AMD</tickerSymbol>
      <isin>US0079031078</isin>
      <isRetired>false</isRetired>
    </security>
    <security>
      <uuid>sec-bnd</uuid>
      <name>Vanguard Total Bond Market</name>
      <currencyCode>USD</currencyCode>
      <tickerSymbol>BND</tickerSymbol>
      <isin>US9219378356</isin>
      <isRetired>false</isRetired>
    </security>
  </securities>
  <accounts>
    <account>
      <uuid>acct-cash-ret</uuid>
      <name>Retirement Cash</name>
      <currencyCode>USD</currencyCode>
      <isRetired>false</isRetired>
    </account>
    <account>
      <uuid>acct-cash-spec</uuid>
      <name>Speculative Cash</name>
      <currencyCode>USD</currencyCode>
      <isRetired>false</isRetired>
    </account>
  </accounts>
  <portfolios>
    <portfolio>
      <uuid>pf-ret</uuid>
      <name>Retirement Savings</name>
      <isRetired>false</isRetired>
      <referenceAccount reference="../../../accounts/account[1]"/>
      <transactions>
        <!-- Correct BND Transactions -->
        <portfolio-transaction>
          <uuid>txn-bnd-01</uuid>
          <date>2024-01-10T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>725000</amount>
          <shares>10000000000</shares>
          <note>Keep here</note>
          <security reference="../../../../../securities/security[3]"/>
          <crossEntry class="buysell">
            <portfolio reference="../../.."/>
            <portfolioTransaction reference="../.."/>
            <account reference="../../../../../accounts/account[1]"/>
            <accountTransaction>
              <uuid>txn-bnd-01-cash</uuid>
              <date>2024-01-10T00:00</date>
              <currencyCode>USD</currencyCode>
              <amount>725000</amount>
              <shares>0</shares>
              <type>WITHDRAWAL</type>
              <crossEntry class="buysell" reference="../.."/>
            </accountTransaction>
          </crossEntry>
          <type>BUY</type>
        </portfolio-transaction>
        <portfolio-transaction>
          <uuid>txn-bnd-02</uuid>
          <date>2024-04-01T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>359000</amount>
          <shares>5000000000</shares>
          <note>Keep here</note>
          <security reference="../../../../../securities/security[3]"/>
          <crossEntry class="buysell">
            <portfolio reference="../../.."/>
            <portfolioTransaction reference="../.."/>
            <account reference="../../../../../accounts/account[1]"/>
            <accountTransaction>
              <uuid>txn-bnd-02-cash</uuid>
              <date>2024-04-01T00:00</date>
              <currencyCode>USD</currencyCode>
              <amount>359000</amount>
              <shares>0</shares>
              <type>WITHDRAWAL</type>
              <crossEntry class="buysell" reference="../.."/>
            </accountTransaction>
          </crossEntry>
          <type>BUY</type>
        </portfolio-transaction>

        <!-- Misassigned NVDA Transactions (Should be in Speculative) -->
        <portfolio-transaction>
          <uuid>txn-nvda-01</uuid>
          <date>2024-02-15T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>726580</amount>
          <shares>1000000000</shares>
          <note>Move to Speculative</note>
          <security reference="../../../../../securities/security[1]"/>
          <crossEntry class="buysell">
            <portfolio reference="../../.."/>
            <portfolioTransaction reference="../.."/>
            <account reference="../../../../../accounts/account[1]"/>
            <accountTransaction>
              <uuid>txn-nvda-01-cash</uuid>
              <date>2024-02-15T00:00</date>
              <currencyCode>USD</currencyCode>
              <amount>726580</amount>
              <shares>0</shares>
              <type>WITHDRAWAL</type>
              <crossEntry class="buysell" reference="../.."/>
            </accountTransaction>
          </crossEntry>
          <type>BUY</type>
        </portfolio-transaction>
        <portfolio-transaction>
          <uuid>txn-nvda-02</uuid>
          <date>2024-03-01T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>411395</amount>
          <shares>500000000</shares>
          <note>Move to Speculative</note>
          <security reference="../../../../../securities/security[1]"/>
          <crossEntry class="buysell">
            <portfolio reference="../../.."/>
            <portfolioTransaction reference="../.."/>
            <account reference="../../../../../accounts/account[1]"/>
            <accountTransaction>
              <uuid>txn-nvda-02-cash</uuid>
              <date>2024-03-01T00:00</date>
              <currencyCode>USD</currencyCode>
              <amount>411395</amount>
              <shares>0</shares>
              <type>WITHDRAWAL</type>
              <crossEntry class="buysell" reference="../.."/>
            </accountTransaction>
          </crossEntry>
          <type>BUY</type>
        </portfolio-transaction>

        <!-- Misassigned AMD Transactions (Should be in Speculative) -->
        <portfolio-transaction>
          <uuid>txn-amd-01</uuid>
          <date>2024-02-20T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>248025</amount>
          <shares>1500000000</shares>
          <note>Move to Speculative</note>
          <security reference="../../../../../securities/security[2]"/>
          <crossEntry class="buysell">
            <portfolio reference="../../.."/>
            <portfolioTransaction reference="../.."/>
            <account reference="../../../../../accounts/account[1]"/>
            <accountTransaction>
              <uuid>txn-amd-01-cash</uuid>
              <date>2024-02-20T00:00</date>
              <currencyCode>USD</currencyCode>
              <amount>248025</amount>
              <shares>0</shares>
              <type>WITHDRAWAL</type>
              <crossEntry class="buysell" reference="../.."/>
            </accountTransaction>
          </crossEntry>
          <type>BUY</type>
        </portfolio-transaction>
        <portfolio-transaction>
          <uuid>txn-amd-02</uuid>
          <date>2024-03-05T00:00</date>
          <currencyCode>USD</currencyCode>
          <amount>205130</amount>
          <shares>1000000000</shares>
          <note>Move to Speculative</note>
          <security reference="../../../../../securities/security[2]"/>
          <crossEntry class="buysell">
            <portfolio reference="../../.."/>
            <portfolioTransaction reference="../.."/>
            <account reference="../../../../../accounts/account[1]"/>
            <accountTransaction>
              <uuid>txn-amd-02-cash</uuid>
              <date>2024-03-05T00:00</date>
              <currencyCode>USD</currencyCode>
              <amount>205130</amount>
              <shares>0</shares>
              <type>WITHDRAWAL</type>
              <crossEntry class="buysell" reference="../.."/>
            </accountTransaction>
          </crossEntry>
          <type>BUY</type>
        </portfolio-transaction>
      </transactions>
    </portfolio>
    <portfolio>
      <uuid>pf-spec</uuid>
      <name>Speculative Tech</name>
      <isRetired>false</isRetired>
      <referenceAccount reference="../../../accounts/account[2]"/>
      <transactions/>
    </portfolio>
  </portfolios>
</client>
XMLEOF

chown ga:ga /home/ga/Documents/PortfolioData/misassigned_trades.xml

# Ensure PP is running
if ! pgrep -f "PortfolioPerformance" > /dev/null; then
    su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"
    sleep 10
    wait_for_pp_window 60
fi

# Maximize
WID=$(wmctrl -l | grep -i "Portfolio\|unnamed" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    wmctrl -ia "$WID" 2>/dev/null || true
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Open the file
open_file_in_pp /home/ga/Documents/PortfolioData/misassigned_trades.xml 15

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="