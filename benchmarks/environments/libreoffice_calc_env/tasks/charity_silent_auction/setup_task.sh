#!/bin/bash
# set -euo pipefail

echo "=== Setting up Charity Silent Auction Task ==="

source /workspace/scripts/task_utils.sh

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create Python script to generate the auction spreadsheet
cat > /tmp/create_auction_spreadsheet.py << 'PYEOF'
#!/usr/bin/env python3
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

def add_cell(row, value, value_type='string'):
    """Helper to add a cell to a row"""
    cell = TableCell(valuetype=value_type)
    if value_type == 'float':
        cell.setAttribute('value', str(value))
        p = P(text=str(value))
    else:
        p = P(text=str(value))
    cell.addElement(p)
    row.addElement(cell)
    return cell

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Sheet 1: Items
items_table = Table(name="Items")
doc.spreadsheet.addElement(items_table)

# Items header
header_row = TableRow()
for header in ["Item ID", "Description", "Donor", "Starting Bid", "Reserve Price"]:
    add_cell(header_row, header, 'string')
items_table.addElement(header_row)

# Items data
items_data = [
    ["A001", "Weekend Cabin Getaway", "Mountain Retreats LLC", 200, 250],
    ["A002", "Dinner for Two at Bella's", "Bella's Restaurant", 75, 100],
    ["A003", "Professional Photography Session", "Smith Photography", 150, 200],
    ["A004", "Handmade Quilt", "Local Quilters Guild", 100, 120],
    ["A005", "Golf Foursome Package", "Pine Valley Golf Club", 300, 400],
    ["A006", "Wine Tasting for 4", "Valley Vineyards", 80, 100],
    ["A007", "Spa Day Package", "Serenity Spa", 120, 150],
    ["A008", "Signed Sports Memorabilia", "Anonymous Donor", 50, 75],
    ["A009", "Art Print Collection", "Local Artist Collective", 40, 50],
    ["A010", "Cooking Class", "Chef Maria's Kitchen", 60, 80]
]

for item in items_data:
    row = TableRow()
    add_cell(row, item[0], 'string')  # Item ID
    add_cell(row, item[1], 'string')  # Description
    add_cell(row, item[2], 'string')  # Donor
    add_cell(row, item[3], 'float')   # Starting Bid
    add_cell(row, item[4], 'float')   # Reserve Price
    items_table.addElement(row)

# Sheet 2: Bids
bids_table = Table(name="Bids")
doc.spreadsheet.addElement(bids_table)

# Bids header
header_row = TableRow()
for header in ["Timestamp", "Item ID", "Bidder Number", "Bid Amount"]:
    add_cell(header_row, header, 'string')
bids_table.addElement(header_row)

# Bids data (realistic auction scenario with various outcomes)
bids_data = [
    # A001 - Cabin - successful, multiple bids
    ["2024-01-20 14:15", "A001", "B105", 200],
    ["2024-01-20 14:32", "A001", "B112", 225],
    ["2024-01-20 15:10", "A001", "B105", 250],
    ["2024-01-20 15:45", "A001", "B118", 275],
    
    # A002 - Dinner - below reserve
    ["2024-01-20 14:20", "A002", "B103", 75],
    ["2024-01-20 14:55", "A002", "B109", 85],
    
    # A003 - Photography - successful
    ["2024-01-20 14:25", "A003", "B107", 150],
    ["2024-01-20 15:20", "A003", "B115", 175],
    ["2024-01-20 15:50", "A003", "B107", 200],
    
    # A004 - Quilt - meets reserve exactly
    ["2024-01-20 14:30", "A004", "B110", 100],
    ["2024-01-20 15:15", "A004", "B114", 115],
    ["2024-01-20 15:40", "A004", "B110", 130],
    
    # A005 - Golf - NO BIDS
    
    # A006 - Wine Tasting - successful, competitive
    ["2024-01-20 14:18", "A006", "B102", 80],
    ["2024-01-20 14:40", "A006", "B108", 90],
    ["2024-01-20 15:05", "A006", "B116", 100],
    ["2024-01-20 15:30", "A006", "B102", 110],
    
    # A007 - Spa - below reserve
    ["2024-01-20 14:22", "A007", "B104", 120],
    ["2024-01-20 14:50", "A007", "B111", 135],
    
    # A008 - Sports Memorabilia - successful
    ["2024-01-20 14:35", "A008", "B106", 50],
    ["2024-01-20 15:00", "A008", "B113", 60],
    ["2024-01-20 15:25", "A008", "B106", 70],
    ["2024-01-20 15:55", "A008", "B117", 85],
    
    # A009 - Art Print - NO BIDS
    
    # A010 - Cooking Class - successful, last minute bid
    ["2024-01-20 15:58", "A010", "B119", 85]
]

for bid in bids_data:
    row = TableRow()
    add_cell(row, bid[0], 'string')   # Timestamp
    add_cell(row, bid[1], 'string')   # Item ID
    add_cell(row, bid[2], 'string')   # Bidder Number
    add_cell(row, bid[3], 'float')    # Bid Amount
    bids_table.addElement(row)

# Sheet 3: Bidders
bidders_table = Table(name="Bidders")
doc.spreadsheet.addElement(bidders_table)

# Bidders header
header_row = TableRow()
for header in ["Bidder Number", "Name", "Phone", "Payment Method"]:
    add_cell(header_row, header, 'string')
bidders_table.addElement(header_row)

# Bidders data
bidders_data = [
    ["B102", "Sarah Johnson", "555-0102", "Credit Card"],
    ["B103", "Michael Chen", "555-0103", "Cash"],
    ["B104", "Emily Rodriguez", "555-0104", "Check"],
    ["B105", "David Thompson", "555-0105", "Credit Card"],
    ["B106", "Jessica Williams", "555-0106", "Credit Card"],
    ["B107", "James Martinez", "555-0107", "Cash"],
    ["B108", "Amanda Davis", "555-0108", "Credit Card"],
    ["B109", "Robert Garcia", "555-0109", "Check"],
    ["B110", "Linda Anderson", "555-0110", "Credit Card"],
    ["B111", "Christopher Taylor", "555-0111", "Cash"],
    ["B112", "Patricia Wilson", "555-0112", "Credit Card"],
    ["B113", "Daniel Moore", "555-0113", "Check"],
    ["B114", "Nancy Thomas", "555-0114", "Credit Card"],
    ["B115", "Matthew Jackson", "555-0115", "Cash"],
    ["B116", "Karen White", "555-0116", "Credit Card"],
    ["B117", "Joseph Harris", "555-0117", "Check"],
    ["B118", "Susan Martin", "555-0118", "Credit Card"],
    ["B119", "Brian Lee", "555-0119", "Cash"]
]

for bidder in bidders_data:
    row = TableRow()
    for value in bidder:
        add_cell(row, value, 'string')
    bidders_table.addElement(row)

# Sheet 4: Summary (template with headers, agent fills formulas)
summary_table = Table(name="Summary")
doc.spreadsheet.addElement(summary_table)

# Summary instructions row
instr_row = TableRow()
add_cell(instr_row, "INSTRUCTIONS: Complete this summary with formulas to analyze the auction results", 'string')
summary_table.addElement(instr_row)

# Empty row
empty_row = TableRow()
for _ in range(10):
    add_cell(empty_row, "", 'string')
summary_table.addElement(empty_row)

# Summary header
header_row = TableRow()
headers = ["Item ID", "Description", "Starting Bid", "Reserve Price", 
           "Current High Bid", "Winning Bidder Number", "Winning Bidder Name", 
           "Status", "Valid Increment"]
for header in headers:
    add_cell(header_row, header, 'string')
summary_table.addElement(header_row)

# Add template rows for each item (formulas to be added by agent)
for item in items_data:
    row = TableRow()
    add_cell(row, item[0], 'string')  # Item ID (pre-filled)
    add_cell(row, item[1], 'string')  # Description (pre-filled)
    add_cell(row, item[3], 'float')   # Starting Bid (pre-filled)
    add_cell(row, item[4], 'float')   # Reserve Price (pre-filled)
    # Rest should have formulas added by agent
    for _ in range(5):  # Placeholders for formula columns
        add_cell(row, "", 'string')
    summary_table.addElement(row)

# Add calculation summary section
for _ in range(2):
    empty_row = TableRow()
    for _ in range(10):
        add_cell(empty_row, "", 'string')
    summary_table.addElement(empty_row)

# Totals section
totals_labels = [
    "Total Revenue (SOLD items only):",
    "Number of Items Sold:",
    "Number of Items Needing Attention:"
]

for label in totals_labels:
    row = TableRow()
    add_cell(row, label, 'string')
    add_cell(row, "", 'string')  # Placeholder for formula
    for _ in range(8):
        add_cell(row, "", 'string')
    summary_table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/auction_tracker.ods")
print("✅ Created auction spreadsheet successfully")
PYEOF

# Install odfpy if not already installed
pip3 install --quiet odfpy 2>/dev/null || true

# Create the spreadsheet
python3 /tmp/create_auction_spreadsheet.py

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/auction_tracker.ods
sudo chmod 666 /home/ga/Documents/auction_tracker.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/auction_tracker.ods > /tmp/calc_auction_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_auction_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Navigate to Summary sheet
echo "Navigating to Summary sheet..."
safe_xdotool ga :1 key ctrl+Page_Down
safe_xdotool ga :1 key ctrl+Page_Down
safe_xdotool ga :1 key ctrl+Page_Down
sleep 0.5

# Position at first formula cell (E4 - Current High Bid for first item)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Down Down Down
safe_xdotool ga :1 key Right Right Right Right
sleep 0.3

echo "=== Charity Silent Auction Task Setup Complete ==="
echo ""
echo "📋 TASK OVERVIEW:"
echo "  You are managing a charity silent auction. The spreadsheet has 4 sheets:"
echo "  - Items: Auction items with starting bids and reserve prices"
echo "  - Bids: All bids placed during the auction"
echo "  - Bidders: Registered bidder information"
echo "  - Summary: Template to complete with formulas"
echo ""
echo "🎯 YOUR GOAL:"
echo "  Complete the Summary sheet with formulas to:"
echo "  1. Find the current highest bid for each item (column E)"
echo "  2. Identify the winning bidder number (column F)"
echo "  3. Look up the winning bidder name (column G)"
echo "  4. Determine status: SOLD / BELOW RESERVE / NO BIDS (column H)"
echo "  5. Validate bid increments meet requirements (column I)"
echo "  6. Calculate total revenue from sold items"
echo "  7. Count items sold and items needing attention"
echo ""
echo "💡 BUSINESS RULES:"
echo "  - Minimum bid increments:"
echo "    • Starting bid \$0-\$49: minimum \$5 raise"
echo "    • Starting bid \$50-\$199: minimum \$10 raise"
echo "    • Starting bid \$200+: minimum \$25 raise"
echo "  - Items are SOLD only if high bid ≥ reserve price"
echo "  - Items with no bids or bids below reserve need attention"
echo ""
echo "🔧 SUGGESTED FORMULAS:"
echo "  - MAXIFS() to find highest bid per item"
echo "  - VLOOKUP() or INDEX/MATCH to look up bidder names"
echo "  - IF() for status determination"
echo "  - SUMIF() to sum only sold items"
echo "  - COUNTIF() to count by status"