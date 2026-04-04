#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Insurance Inventory Cleanup Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already present
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf
fi

# Create messy home inventory ODS file with realistic inconsistencies
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties
from odf.number import NumberStyle, CurrencyStyle, CurrencySymbol, Number, Text as NumText

import random
from datetime import datetime, timedelta

doc = OpenDocumentSpreadsheet()
table = Table(name="Home Inventory")

# Create header row
header_row = TableRow()
headers = ["Item", "Category", "Room", "Purchase Date", "Purchase Price", "Notes"]
for header in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
table.addElement(header_row)

# Sample data with intentional messiness
items_data = [
    # Item, Category (messy), Room, Date (messy), Price, Notes
    ("Samsung TV 55 inch", "Electronics", "Living Room", "2019-03-15", "1200", ""),
    ("Laptop Dell XPS", "electronic", "Office", "2 years ago", "1500", "need receipt"),
    ("Kitchen Table Oak", "Furniture", "Kitchen", "2018", "800", ""),
    ("Dining Chairs (set of 4)", "furniture ", "Dining Room", "2018", "600", ""),
    ("Sofa Leather", "Furnature", "Living Room", "Jan 2020", "2200", ""),
    ("Wedding Ring Gold", "Jewelry", "Bedroom", "2015-06-20", "3500", "Has appraisal"),
    ("Necklace Diamond", "jewlery", "Bedroom", "2017", "2800", ""),
    ("iPhone 13", "ELECTRONICS", "Personal", "Nov 2021", "999", ""),
    ("Refrigerator", "Appliances", "Kitchen", "2020-05-10", "1800", ""),
    ("Washer/Dryer Set", "Appliance", "Laundry", "3 years ago", "1400", ""),
    ("Microwave", "appliances", "Kitchen", "2021-08-15", "300", ""),
    ("Power Drill", "Tools", "Garage", "2019", "180", ""),
    ("Lawn Mower", "tools", "Garage", "2020-04-20", "450", ""),
    ("Toolbox with tools", "tool", "Garage", "5 years ago", "200", ""),
    ("Bedroom Set", "Furniture", "Master Bedroom", "2017-10-05", "3200", ""),
    ("Desktop Computer", "Electronics", "Office", "2020", "1100", "Custom built"),
    ("Printer Canon", "electronic", "Office", "1 year ago", "250", ""),
    ("Smart Watch", "ELECTRONICS", "Personal", "2022-12-25", "400", "Gift"),
    ("Dishwasher", "Appliance", "Kitchen", "2019-07-20", "650", ""),
    ("Coffee Maker", "appliances", "Kitchen", "2021", "120", ""),
    ("Bookshelf", "furniture", "Office", "2018-03-10", "300", ""),
    ("Dresser", "Furniture", "Bedroom", "2016", "550", ""),
    ("Pearl Earrings", "JEWELRY", "Bedroom", "2019-05-15", "1200", ""),
    ("Tablet iPad", "Electronics", "Living Room", "2021-06-10", "650", ""),
    ("Gaming Console", "electronic", "Living Room", "2020", "500", ""),
    ("Vacuum Cleaner", "Appliances", "Closet", "2020-11-05", "280", ""),
    ("Air Conditioner", "appliance", "Bedroom", "2019", "800", ""),
    ("Desk", "Furniture", "Office", "2017", "400", ""),
    ("Office Chair", "furniture ", "Office", "3 years ago", "350", ""),
    ("Cordless Drill Set", "Tools", "Garage", "2021-03-15", "220", ""),
    ("Ladder", "tools", "Garage", "2018", "150", ""),
    ("Garden Tools Set", "TOOLS", "Garage", "4 years ago", "180", ""),
    ("Bicycle Mountain", "Tools", "Garage", "2019-08-20", "800", "Could be sporting goods"),
    ("Mattress King", "Furniture", "Master Bedroom", "2020-01-15", "1500", ""),
    ("Night Stands (pair)", "furniture", "Master Bedroom", "2020", "400", ""),
    ("Blender", "Appliances", "Kitchen", "2021-04-10", "90", ""),
    ("Toaster Oven", "appliance", "Kitchen", "2 years ago", "85", ""),
    ("Camera Canon DSLR", "Electronics", "Office", "2018-07-15", "1800", ""),
    ("Headphones Bose", "electronic", "Personal", "2022", "350", ""),
    ("Watch Collection (3)", "Jewelry", "Bedroom", "2016-2020", "2500", "Various purchases"),
]

for item_data in items_data:
    row = TableRow()
    
    # Item name (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=item_data[0]))
    row.addElement(cell)
    
    # Category (string, messy)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=item_data[1]))
    row.addElement(cell)
    
    # Room (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=item_data[2]))
    row.addElement(cell)
    
    # Purchase Date (string, messy format)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=item_data[3]))
    row.addElement(cell)
    
    # Purchase Price (float)
    cell = TableCell(valuetype="float", value=item_data[4])
    cell.addElement(P(text=item_data[4]))
    row.addElement(cell)
    
    # Notes (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=item_data[5]))
    row.addElement(cell)
    
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/home_inventory_messy.ods")
print("Created messy home inventory ODS file successfully")
print(f"Total items: {len(items_data)}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/home_inventory_messy.ods
sudo chmod 666 /home/ga/Documents/home_inventory_messy.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/home_inventory_messy.ods > /tmp/calc_inventory_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_inventory_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
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

echo "=== Insurance Inventory Cleanup Task Setup Complete ==="
echo "📋 Scenario: Home inventory data collected after fire scare"
echo "📝 Task: Clean and organize messy inventory data"
echo ""
echo "Required Actions:"
echo "  1. Standardize category names (Electronics, Furniture, Appliances, Jewelry, Tools)"
echo "  2. Normalize date formats to YYYY-MM-DD"
echo "  3. Add 'Age (Years)' column with formula: =DATEDIF(D2,TODAY(),\"Y\")"
echo "  4. Add 'Current Value' column with depreciation formulas"
echo "  5. Add 'Documentation Status' column (NEEDS PHOTO/NEEDS RECEIPT/OK)"
echo "  6. Apply conditional formatting for high-value items"
echo "  7. Create summary statistics with SUMIF formulas"
echo ""
echo "💡 Hints:"
echo "  - Use Find & Replace (Ctrl+H) to fix category variations"
echo "  - Depreciation rates: Electronics 20%, Furniture 10%, Appliances 15%, Jewelry 0%, Tools 8%"
echo "  - Flag items >$1000 current value as needing documentation"