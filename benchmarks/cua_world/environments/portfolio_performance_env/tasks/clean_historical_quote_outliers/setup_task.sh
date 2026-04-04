#!/bin/bash
echo "=== Setting up Clean Historical Quote Outliers task ==="

source /workspace/scripts/task_utils.sh

# Mark task start
mark_task_start

# Ensure directory exists
mkdir -p /home/ga/Documents/PortfolioData

# 1. Create the Portfolio XML with Corrupt Data
# We use Python to generate a valid XML to avoid string escaping issues
python3 -c '
import os
import xml.etree.ElementTree as ET

# PP uses a factor of 100,000,000 for prices
# 130.22 -> 13022000000
FACTOR = 100000000

# Real AMZN close prices for July 2023 (approximate)
quotes = [
    ("2023-07-03", 130.22),
    ("2023-07-05", 130.38),
    ("2023-07-06", 128.36),
    ("2023-07-07", 129.78),
    ("2023-07-10", 127.13),
    ("2023-07-11", 128.78),
    ("2023-07-12", 130.80),
    ("2023-07-13", 134.30),
    ("2023-07-14", 0.01),   # THE GLITCH
    ("2023-07-17", 133.56),
    ("2023-07-18", 132.84),
    ("2023-07-19", 135.36),
    ("2023-07-20", 129.96),
    ("2023-07-21", 130.00),
    ("2023-07-24", 128.68),
    ("2023-07-25", 129.13),
    ("2023-07-26", 128.15),
    ("2023-07-27", 128.25),
    ("2023-07-28", 132.21),
    ("2023-07-31", 133.68)
]

# Build Minimal Valid PP XML
root = ET.Element("client")
ET.SubElement(root, "version").text = "68"
ET.SubElement(root, "baseCurrency").text = "USD"
securities = ET.SubElement(root, "securities")
security = ET.SubElement(securities, "security")

ET.SubElement(security, "uuid").text = "sec-amzn-glitch"
ET.SubElement(security, "name").text = "Amazon.com Inc."
ET.SubElement(security, "currencyCode").text = "USD"
ET.SubElement(security, "isin").text = "US0231351067"
ET.SubElement(security, "tickerSymbol").text = "AMZN"

prices = ET.SubElement(security, "prices")

for date, val in quotes:
    p = ET.SubElement(prices, "price")
    p.set("t", date)
    # Calculate internal long value
    internal_val = int(val * FACTOR)
    p.set("v", str(internal_val))

ET.SubElement(root, "accounts")
ET.SubElement(root, "portfolios")
ET.SubElement(root, "plans")
ET.SubElement(root, "taxonomies")
ET.SubElement(root, "dashboards")
ET.SubElement(root, "settings")

tree = ET.ElementTree(root)
output_file = "/home/ga/Documents/PortfolioData/amzn_glitch.xml"
tree.write(output_file, encoding="UTF-8", xml_declaration=True)
print(f"Created {output_file} with {len(quotes)} quotes.")
'

chown ga:ga /home/ga/Documents/PortfolioData/amzn_glitch.xml

# Record initial state
INITIAL_PRICE_COUNT=$(grep -c '<price ' /home/ga/Documents/PortfolioData/amzn_glitch.xml 2>/dev/null || echo "0")
echo "$INITIAL_PRICE_COUNT" > /tmp/initial_price_count

# Kill any existing PP and relaunch fresh
pkill -f PortfolioPerformance 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 SWT_GTK3=1 GDK_BACKEND=x11 /opt/portfolio-performance/PortfolioPerformance -data /home/ga/.portfolio-performance > /tmp/pp.log 2>&1 &"

# Wait for PP to start
wait_for_pp_window 60

# Maximize
WID=$(wmctrl -l | grep -i "Portfolio\|unnamed" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    wmctrl -ia "$WID" 2>/dev/null || true
    wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any dialogs
sleep 2
xdotool key Escape 2>/dev/null || true
sleep 1

# Open the portfolio file via Ctrl+O (PP ignores file arguments)
open_file_in_pp /home/ga/Documents/PortfolioData/amzn_glitch.xml 15

sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "Initial price count: $INITIAL_PRICE_COUNT"
echo "=== Task setup complete ==="