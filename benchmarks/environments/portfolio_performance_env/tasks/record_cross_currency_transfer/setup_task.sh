#!/bin/bash
echo "=== Setting up record_cross_currency_transfer task ==="

source /workspace/scripts/task_utils.sh

# Mark task start
mark_task_start

# Clean up leftover files
clean_portfolio_data "forex_portfolio.xml"

# Create the portfolio XML with EUR and USD accounts using Python for proper XML structure
# We use UUIDs to ensure validity
python3 -c '
import xml.etree.ElementTree as ET
from xml.dom import minidom
import uuid

def create_uuid():
    return f"uuid-{uuid.uuid4()}"

# Root element
root = ET.Element("client")
ET.SubElement(root, "version").text = "68"
ET.SubElement(root, "baseCurrency").text = "EUR"
ET.SubElement(root, "securities")
ET.SubElement(root, "watchlists")

# Accounts
accounts = ET.SubElement(root, "accounts")

# 1. Sparkasse Giro (EUR)
acct_eur = ET.SubElement(accounts, "account")
ET.SubElement(acct_eur, "uuid").text = create_uuid()
ET.SubElement(acct_eur, "name").text = "Sparkasse Giro"
ET.SubElement(acct_eur, "currencyCode").text = "EUR"
ET.SubElement(acct_eur, "isRetired").text = "false"
txs_eur = ET.SubElement(acct_eur, "transactions")

# Initial Deposit EUR (10,000.00)
tx_dep = ET.SubElement(txs_eur, "account-transaction")
ET.SubElement(tx_dep, "uuid").text = create_uuid()
ET.SubElement(tx_dep, "date").text = "2024-01-01T00:00"
ET.SubElement(tx_dep, "currencyCode").text = "EUR"
ET.SubElement(tx_dep, "amount").text = "1000000"
ET.SubElement(tx_dep, "shares").text = "0"
ET.SubElement(tx_dep, "type").text = "DEPOSIT"
ET.SubElement(tx_dep, "note").text = "Start Balance"

# 2. Interactive Brokers (USD)
acct_usd = ET.SubElement(accounts, "account")
ET.SubElement(acct_usd, "uuid").text = create_uuid()
ET.SubElement(acct_usd, "name").text = "Interactive Brokers"
ET.SubElement(acct_usd, "currencyCode").text = "USD"
ET.SubElement(acct_usd, "isRetired").text = "false"
ET.SubElement(acct_usd, "transactions")

# Portfolios (Required structure)
portfolios = ET.SubElement(root, "portfolios")
pf = ET.SubElement(portfolios, "portfolio")
ET.SubElement(pf, "uuid").text = create_uuid()
ET.SubElement(pf, "name").text = "Main Portfolio"
ET.SubElement(pf, "isRetired").text = "false"
ref = ET.SubElement(pf, "referenceAccount")
ref.set("reference", "../../../accounts/account[2]") # Refers to USD account usually, or create generic
ET.SubElement(pf, "transactions")

# Other required empty sections
ET.SubElement(root, "plans")
ET.SubElement(root, "taxonomies")
ET.SubElement(root, "dashboards")
ET.SubElement(root, "properties")
settings = ET.SubElement(root, "settings")
ET.SubElement(settings, "bookmarks")
ET.SubElement(settings, "attributeTypes")
ET.SubElement(settings, "configurationSets")

# Save formatted XML
xml_str = minidom.parseString(ET.tostring(root)).toprettyxml(indent="  ")
# Remove empty lines caused by minidom
xml_str = "\n".join([line for line in xml_str.split("\n") if line.strip()])

with open("/home/ga/Documents/PortfolioData/forex_portfolio.xml", "w") as f:
    f.write(xml_str)
'

chown ga:ga /home/ga/Documents/PortfolioData/forex_portfolio.xml

# Ensure PP is running
if ! pgrep -f "PortfolioPerformance" > /dev/null; then
    su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"
    sleep 10
fi

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
open_file_in_pp "/home/ga/Documents/PortfolioData/forex_portfolio.xml" 15

# Screenshot initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="