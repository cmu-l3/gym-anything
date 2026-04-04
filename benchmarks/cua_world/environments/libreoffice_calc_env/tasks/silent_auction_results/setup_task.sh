#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Silent Auction Results Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create auction data spreadsheet using Python
echo "Creating auction data spreadsheet..."
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, CurrencyStyle, CurrencySymbol, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Auction Results"
table = Table(name="Auction Results")
doc.spreadsheet.addElement(table)

# Header row
headers = [
    "Item ID", "Item Name", "Starting Bid", "Reserve Price",
    "Bid 1", "Bidder 1", "Bid 2", "Bidder 2", 
    "Bid 3", "Bidder 3", "Bid 4", "Bidder 4",
    "Bid 5", "Bidder 5"
]

header_row = TableRow()
for header in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
table.addElement(header_row)

# Auction items data with realistic messiness
# Format: [ID, Name, Starting, Reserve, Bid1, Bidder1, Bid2, Bidder2, Bid3, Bidder3, Bid4, Bidder4, Bid5, Bidder5]
items_data = [
    [1, "Vintage Wine Basket", 50, 75, "$80", "B118", "$95", "B201", "$110", "B042", None, None, None, None],
    [2, "Weekend Spa Package", 200, 300, "250", "B118", "$320", "B201", "315", "B089", "$350", "B042", None, None],
    [3, "Golf Foursome", 150, 200, "$175", "B201", None, None, None, None, None, None, None, None],
    [4, "Restaurant Gift Card", 25, 50, None, None, None, None, None, None, None, None, None, None],
    [5, "Art Print (Signed)", 100, 150, "$120", "B089", "$165", "B118", "$180", "B201", None, None, None, None],
    [6, "Concert Tickets (2)", 80, 120, "90", "B042", "$100", "B201", None, None, None, None, None, None],
    [7, "Cooking Class", 60, 100, "$110", "B118", "$125", "B089", "$130", "B201", None, None, None, None],
    [8, "Jewelry Set", 200, 250, "220", "B201", "$240", "B042", None, None, None, None, None, None],
    [9, "Kayak Rental Day", 40, 60, "$55", "B089", "$70", "B118", "$75", "B201", None, None, None, None],
    [10, "Photography Session", 150, 200, "180", "B042", None, None, None, None, None, None, None, None],
    [11, "Handmade Quilt", 300, 400, "$350", "B118", "$425", "B201", "$450", "B089", None, None, None, None],
    [12, "Yoga Class Pass", 50, 75, "60", "B201", "$65", "B042", None, None, None, None, None, None],
    [13, "Garden Tools Set", 75, 100, "$85", "B089", None, None, None, None, None, None, None, None],
    [14, "Coffee Maker", 80, 120, None, None, None, None, None, None, None, None, None, None],
    [15, "Board Game Bundle", 60, 80, "$95", "B118", "$100", "B201", "$105", "B042", None, None, None, None],
    [16, "Bookstore Gift Card", 30, 50, "40", "B089", None, None, None, None, None, None, None, None],
    [17, "Pottery Workshop", 100, 150, "$140", "B201", "$165", "B118", "$170", "B089", None, None, None, None],
    [18, "Wine Tasting Tour", 120, 180, "150", "B042", "$175", "B201", None, None, None, None, None, None],
    [19, "Pet Portrait", 80, 100, "$90", "B118", "$105", "B201", "$115", "B089", None, None, None, None],
    [20, "Camping Gear", 150, 200, "170", "B042", None, None, None, None, None, None, None, None],
]

# Add data rows
for item in items_data:
    row = TableRow()
    for i, value in enumerate(item):
        cell = TableCell()
        if value is None:
            # Empty cell
            pass
        elif isinstance(value, str):
            # String value (including bids with $ symbol)
            cell.setAttribute('valuetype', 'string')
            cell.addElement(P(text=value))
        elif isinstance(value, (int, float)):
            # Numeric value
            if i >= 2 and i <= 3:  # Starting Bid and Reserve Price columns
                # Store as float for prices
                cell.setAttribute('valuetype', 'float')
                cell.setAttribute('value', str(float(value)))
                cell.addElement(P(text=str(value)))
            else:
                # Regular number
                cell.setAttribute('valuetype', 'float')
                cell.setAttribute('value', str(float(value)))
                cell.addElement(P(text=str(value)))
        row.addElement(cell)
    table.addElement(row)

# Add some empty rows for summary statistics area
for _ in range(10):
    row = TableRow()
    for _ in range(20):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
output_path = "/home/ga/Documents/auction_items.ods"
doc.save(output_path)
print(f"Created auction spreadsheet: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/auction_items.ods
sudo chmod 666 /home/ga/Documents/auction_items.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/auction_items.ods > /tmp/calc_auction_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_auction_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Silent Auction Results Task Setup Complete ==="
echo ""
echo "🎯 URGENT: Auction Results Needed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 TASK: Process auction bid data to determine winners and revenue"
echo ""
echo "⚠️  NOTE: Some bid amounts have '$' symbols (stored as text) - handle appropriately!"
echo ""
echo "✅ REQUIRED COLUMNS TO CREATE:"
echo "   Column O: Highest Bid (use MAX formula across bid columns)"
echo "   Column P: Winning Bidder (identify which bidder made highest bid)"
echo "   Column Q: Sale Status (SOLD/NOT SOLD/NO BIDS based on reserve price)"
echo "   Column R: Final Price (highest bid if SOLD, otherwise 0 or blank)"
echo ""
echo "📊 REQUIRED SUMMARY STATISTICS (create below data):"
echo "   - Total Revenue Raised"
echo "   - Items Successfully Sold (count)"
echo "   - Items Not Sold (count)"
echo "   - Highest Sale Price"
echo ""
echo "💡 HINTS:"
echo "   - Bid columns: E, G, I, K, M (every other column starting from E)"
echo "   - Bidder columns: F, H, J, L, N (every other column starting from F)"
echo "   - Reserve price must be met for item to be SOLD"
echo "   - Empty bid cells = no bid submitted"
echo "   - Use VALUE() or handle text-formatted numbers with $ symbols"
echo ""
echo "⏰ Time pressure: People waiting for results!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"