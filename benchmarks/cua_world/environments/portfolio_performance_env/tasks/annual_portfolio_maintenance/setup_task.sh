#!/bin/bash
echo "=== Setting up annual_portfolio_maintenance task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (BEFORE any file creation)
mark_task_start

# Clean portfolio data directory, keeping nothing
clean_portfolio_data ""

PORTFOLIO_FILE="/home/ga/Documents/PortfolioData/managed_portfolio.xml"

# Generate the pre-loaded portfolio XML
# This portfolio has:
#   - EUR base currency
#   - 4 securities (NVIDIA, Allianz, Vanguard FTSE AW, iShares EUR Corp Bond)
#   - 1 deposit account (Verrechnungskonto) with EUR 50,000
#   - 1 securities account (Wertpapierdepot) with 4 BUY transactions
#   - Empty <taxonomies/> and <plans/> (agent must create these)
#   - Empty <events/> on NVIDIA (agent must record stock split here)
#
# CRITICAL: All <account> elements include <transactions> children to prevent
# the NullPointerException that crashes PP's taxonomy view when the element is missing.

cat > "$PORTFOLIO_FILE" << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<client>
  <version>68</version>
  <baseCurrency>EUR</baseCurrency>
  <securities>
    <security>
      <uuid>sec-nvidia-001</uuid>
      <name>NVIDIA Corp</name>
      <currencyCode>EUR</currencyCode>
      <isin>US67066G1040</isin>
      <tickerSymbol>NVDA</tickerSymbol>
      <feed>MANUAL</feed>
      <prices>
        <price t="2024-01-02" v="48200000000"/>
        <price t="2024-02-01" v="62500000000"/>
        <price t="2024-03-01" v="80000000000"/>
        <price t="2024-03-15" v="81500000000"/>
        <price t="2024-04-01" v="79000000000"/>
        <price t="2024-05-01" v="88000000000"/>
        <price t="2024-06-03" v="110000000000"/>
      </prices>
      <events/>
      <isRetired>false</isRetired>
    </security>
    <security>
      <uuid>sec-allianz-002</uuid>
      <name>Allianz SE</name>
      <currencyCode>EUR</currencyCode>
      <isin>DE0008404005</isin>
      <tickerSymbol>ALV</tickerSymbol>
      <feed>MANUAL</feed>
      <prices>
        <price t="2024-01-02" v="24000000000"/>
        <price t="2024-02-01" v="24200000000"/>
        <price t="2024-03-01" v="24500000000"/>
        <price t="2024-03-15" v="24830000000"/>
        <price t="2024-04-01" v="25100000000"/>
        <price t="2024-05-01" v="26200000000"/>
        <price t="2024-06-01" v="26500000000"/>
      </prices>
      <events/>
      <isRetired>false</isRetired>
    </security>
    <security>
      <uuid>sec-vanguard-003</uuid>
      <name>Vanguard FTSE All-World UCITS ETF</name>
      <currencyCode>EUR</currencyCode>
      <isin>IE00B3RBWM25</isin>
      <tickerSymbol>VWRL</tickerSymbol>
      <feed>MANUAL</feed>
      <prices>
        <price t="2024-01-02" v="10800000000"/>
        <price t="2024-02-01" v="11000000000"/>
        <price t="2024-03-01" v="11400000000"/>
        <price t="2024-03-15" v="11540000000"/>
        <price t="2024-04-01" v="11680000000"/>
        <price t="2024-05-01" v="11900000000"/>
        <price t="2024-06-01" v="12100000000"/>
      </prices>
      <events/>
      <isRetired>false</isRetired>
    </security>
    <security>
      <uuid>sec-ishares-004</uuid>
      <name>iShares Core EUR Corp Bond UCITS ETF</name>
      <currencyCode>EUR</currencyCode>
      <isin>IE00B3F81R35</isin>
      <tickerSymbol>IEAC</tickerSymbol>
      <feed>MANUAL</feed>
      <prices>
        <price t="2024-01-02" v="9900000000"/>
        <price t="2024-02-01" v="9920000000"/>
        <price t="2024-03-01" v="9950000000"/>
        <price t="2024-03-15" v="9985000000"/>
        <price t="2024-04-01" v="10020000000"/>
        <price t="2024-05-01" v="10050000000"/>
        <price t="2024-06-01" v="10080000000"/>
      </prices>
      <events/>
      <isRetired>false</isRetired>
    </security>
  </securities>
  <accounts>
    <account>
      <uuid>acct-clearing-001</uuid>
      <name>Verrechnungskonto</name>
      <currencyCode>EUR</currencyCode>
      <transactions>
        <account-transaction>
          <uuid>txn-dep-initial</uuid>
          <date>2024-01-02T00:00</date>
          <currencyCode>EUR</currencyCode>
          <amount>5000000</amount>
          <type>DEPOSIT</type>
        </account-transaction>
      </transactions>
    </account>
  </accounts>
  <portfolios>
    <portfolio>
      <uuid>pf-depot-001</uuid>
      <name>Wertpapierdepot</name>
      <referenceAccount reference="../../../accounts/account"/>
      <transactions>
        <portfolio-transaction>
          <uuid>txn-buy-nvda</uuid>
          <date>2024-03-15T00:00</date>
          <currencyCode>EUR</currencyCode>
          <amount>815000</amount>
          <shares>1000000000</shares>
          <security reference="../../../../../securities/security"/>
          <type>BUY</type>
          <units>
            <unit type="FEE">
              <amount currency="EUR" amount="990"/>
            </unit>
          </units>
        </portfolio-transaction>
        <portfolio-transaction>
          <uuid>txn-buy-alv</uuid>
          <date>2024-03-15T00:00</date>
          <currencyCode>EUR</currencyCode>
          <amount>372450</amount>
          <shares>1500000000</shares>
          <security reference="../../../../../securities/security[2]"/>
          <type>BUY</type>
          <units>
            <unit type="FEE">
              <amount currency="EUR" amount="990"/>
            </unit>
          </units>
        </portfolio-transaction>
        <portfolio-transaction>
          <uuid>txn-buy-vwrl</uuid>
          <date>2024-03-15T00:00</date>
          <currencyCode>EUR</currencyCode>
          <amount>923200</amount>
          <shares>8000000000</shares>
          <security reference="../../../../../securities/security[3]"/>
          <type>BUY</type>
          <units>
            <unit type="FEE">
              <amount currency="EUR" amount="590"/>
            </unit>
          </units>
        </portfolio-transaction>
        <portfolio-transaction>
          <uuid>txn-buy-ieac</uuid>
          <date>2024-03-15T00:00</date>
          <currencyCode>EUR</currencyCode>
          <amount>998500</amount>
          <shares>10000000000</shares>
          <security reference="../../../../../securities/security[4]"/>
          <type>BUY</type>
          <units>
            <unit type="FEE">
              <amount currency="EUR" amount="590"/>
            </unit>
          </units>
        </portfolio-transaction>
      </transactions>
    </portfolio>
  </portfolios>
  <taxonomies></taxonomies>
  <plans></plans>
</client>
XMLEOF

chown ga:ga "$PORTFOLIO_FILE"
echo "Portfolio file created at $PORTFOLIO_FILE"

# Kill any existing Portfolio Performance instances
pkill -f "PortfolioPerformance" 2>/dev/null || true
sleep 2

# Launch Portfolio Performance as user ga
su - ga -c "DISPLAY=:1 /opt/portfolio-performance/PortfolioPerformance &"
sleep 3

# Wait for PP window to appear
wait_for_pp_window 60

# Maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs (Updates Available, error dialogs, etc.)
# The "Error on updating" dialog has an OK button that responds to Enter, not Escape
for i in 1 2 3; do
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Open the portfolio file
open_file_in_pp "$PORTFOLIO_FILE" 30

sleep 3

# Take initial screenshot for debugging
take_screenshot /tmp/task_initial_state.png

echo "=== annual_portfolio_maintenance task setup complete ==="
