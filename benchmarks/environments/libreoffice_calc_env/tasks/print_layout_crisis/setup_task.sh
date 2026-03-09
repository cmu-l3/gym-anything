#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Print Layout Crisis Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create realistic inventory spreadsheet with poor print layout using Python
echo "Creating messy inventory spreadsheet..."
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell, TableColumn
from odf.text import P
from odf.style import Style, TableColumnProperties
from odf import dc, meta

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add metadata
doc.meta.addElement(dc.Title(text="Business Inventory - Needs Print Layout Fix"))
doc.meta.addElement(dc.Description(text="Inventory spreadsheet with poor print configuration"))

# Create column styles with intentionally poor widths
# Some columns are way too wide, causing horizontal overflow
col_style_wide = Style(name="ColWide", family="table-column")
col_style_wide.addElement(TableColumnProperties(columnwidth="6cm"))  # Very wide

col_style_medium = Style(name="ColMedium", family="table-column")
col_style_medium.addElement(TableColumnProperties(columnwidth="3.5cm"))

col_style_narrow = Style(name="ColNarrow", family="table-column")
col_style_narrow.addElement(TableColumnProperties(columnwidth="2.5cm"))

doc.automaticstyles.addElement(col_style_wide)
doc.automaticstyles.addElement(col_style_medium)
doc.automaticstyles.addElement(col_style_narrow)

# Create table
table = Table(name="Inventory")

# Add columns with poor width distribution
# SKU, Product Name, Category, Description, Price, Stock, Supplier, Location, Notes
columns_config = [
    ("ColNarrow", 1),    # SKU
    ("ColMedium", 1),    # Product Name
    ("ColNarrow", 1),    # Category
    ("ColWide", 1),      # Description (excessively wide)
    ("ColNarrow", 1),    # Price
    ("ColNarrow", 1),    # Stock
    ("ColMedium", 1),    # Supplier
    ("ColMedium", 1),    # Location
    ("ColWide", 1),      # Notes (excessively wide)
]

for style_name, count in columns_config:
    col = TableColumn(stylename=style_name)
    table.addElement(col)

# Header row
header_row = TableRow()
headers = ["SKU", "Product Name", "Category", "Description", "Unit Price", "Stock Qty", "Supplier", "Warehouse Location", "Notes"]
for header_text in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
table.addElement(header_row)

# Sample inventory data (50 rows for realism)
import random

categories = ["Electronics", "Office Supplies", "Hardware", "Furniture", "Software"]
suppliers = ["Global Tech Inc", "Office Depot", "Hardware Warehouse", "Furniture Direct", "Software Solutions"]
locations = ["Warehouse A-1", "Warehouse A-2", "Warehouse B-1", "Warehouse B-2", "Storage C-1"]

products_by_category = {
    "Electronics": ["Wireless Mouse", "USB Keyboard", "Monitor 24in", "Laptop Charger", "HDMI Cable", "Webcam HD"],
    "Office Supplies": ["Printer Paper", "Stapler Heavy Duty", "File Folders", "Desk Organizer", "Whiteboard Markers"],
    "Hardware": ["Screwdriver Set", "Drill Bits", "Measuring Tape", "Hammer", "Wrench Set"],
    "Furniture": ["Office Chair", "Standing Desk", "Filing Cabinet", "Bookshelf", "Desk Lamp"],
    "Software": ["Office Suite License", "Antivirus Software", "Project Management Tool", "Design Software"]
}

for i in range(1, 51):
    row = TableRow()
    
    # SKU
    sku = f"INV-{1000 + i}"
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=sku))
    row.addElement(cell)
    
    # Product Name
    category = random.choice(categories)
    product = random.choice(products_by_category[category])
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=f"{product} #{i}"))
    row.addElement(cell)
    
    # Category
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=category))
    row.addElement(cell)
    
    # Description (intentionally verbose)
    descriptions = [
        "High-quality commercial grade product with extended warranty coverage and premium build quality",
        "Professional series item designed for heavy daily use in office environments with ergonomic features",
        "Industrial strength construction meeting all safety standards and regulatory compliance requirements",
        "Budget-friendly option providing excellent value while maintaining acceptable quality standards",
        "Premium tier product with advanced features and superior performance characteristics"
    ]
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=random.choice(descriptions)))
    row.addElement(cell)
    
    # Price
    price = round(random.uniform(15.99, 499.99), 2)
    cell = TableCell(valuetype="float", value=str(price))
    cell.addElement(P(text=f"${price:.2f}"))
    row.addElement(cell)
    
    # Stock
    stock = random.randint(5, 250)
    cell = TableCell(valuetype="float", value=str(stock))
    cell.addElement(P(text=str(stock)))
    row.addElement(cell)
    
    # Supplier
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=random.choice(suppliers)))
    row.addElement(cell)
    
    # Location
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=random.choice(locations)))
    row.addElement(cell)
    
    # Notes (intentionally verbose)
    notes = [
        "Reorder when stock drops below 20 units. Popular item with high turnover rate.",
        "Seasonal item - increase stock before Q4. Check supplier lead times regularly.",
        "Bulk pricing available for orders over 50 units. Negotiate annually.",
        "Customer favorite - maintain minimum stock level at all times. Fast shipping required.",
        "New product line - monitor sales velocity and adjust inventory accordingly."
    ]
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=random.choice(notes)))
    row.addElement(cell)
    
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save with DEFAULT page settings (portrait, no scaling, default margins)
# This creates the "disaster" print layout that needs fixing
doc.save("/home/ga/Documents/inventory_to_print.ods")
print("✅ Created messy inventory spreadsheet with poor print layout")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/inventory_to_print.ods
sudo chmod 666 /home/ga/Documents/inventory_to_print.ods

# Verify file was created
if [ ! -f /home/ga/Documents/inventory_to_print.ods ]; then
    echo "ERROR: Failed to create inventory spreadsheet"
    exit 1
fi

echo "✅ Inventory spreadsheet created: $(ls -lh /home/ga/Documents/inventory_to_print.ods)"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/inventory_to_print.ods > /tmp/calc_print_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_print_task.log
    # exit 1  # Don't exit, allow task to continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # exit 1  # Don't exit, allow task to continue
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window for better visibility
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Position cursor at A1 for consistency
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Print Layout Crisis Task Setup Complete ==="
echo ""
echo "🚨 CRISIS SITUATION:"
echo "   The inventory spreadsheet will print across 3-4 pages horizontally!"
echo "   Critical columns will be cut off and split across separate pages."
echo ""
echo "📋 YOUR MISSION:"
echo "   Fix the print layout to fit on 1-2 pages wide maximum"
echo ""
echo "💡 HINTS:"
echo "   1. Check Print Preview (Ctrl+Shift+P) to see the disaster"
echo "   2. Go to Format → Page to access page setup"
echo "   3. Change orientation to Landscape (Page tab)"
echo "   4. Configure scaling (Sheet tab): try 85% or fit to 1-2 pages wide"
echo "   5. Narrow wide columns: Description and Notes columns"
echo "   6. Adjust margins to 0.75in or 2cm (Page tab)"
echo "   7. Verify in Print Preview again"
echo "   8. Save the file (Ctrl+S)"