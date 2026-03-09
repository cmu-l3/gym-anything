#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Version Diff Highlighter Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install required Python packages if not already installed
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
    sudo apt-get update && sudo apt-get install -y python3-odf
fi

# Create the spreadsheet with two versions using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
import json
import os

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Product data for Version 1
version1_data = [
    ["Product ID", "Product Name", "Category", "Unit Price", "Stock Quantity", "Last Updated"],
    ["P1001", "Wireless Mouse", "Electronics", 24.99, 150, "2024-01-15"],
    ["P1002", "USB-C Cable", "Accessories", 12.99, 300, "2024-01-18"],
    ["P1003", "Laptop Stand", "Furniture", 45.00, 75, "2024-01-20"],
    ["P1004", "Keyboard", "Electronics", 89.99, 120, "2024-01-22"],
    ["P1005", "Monitor Arm", "Furniture", 125.00, 45, "2024-01-25"],
    ["P1006", "Webcam HD", "Electronics", 79.99, 90, "2024-01-28"],
    ["P1007", "Desk Lamp", "Furniture", 34.99, 200, "2024-02-01"],
    ["P1008", "Mouse Pad", "Accessories", 9.99, 500, "2024-02-03"],
    ["P1009", "HDMI Cable", "Accessories", 15.99, 250, "2024-02-05"],
    ["P1010", "Phone Stand", "Accessories", 18.99, 180, "2024-02-08"]
]

# Version 2 data with intentional changes
# Changes: P1001 price, P1003 price, P1004 quantity, P1006 name, P1008 category, P1009 price
version2_data = [
    ["Product ID", "Product Name", "Category", "Unit Price", "Stock Quantity", "Last Updated"],
    ["P1001", "Wireless Mouse", "Electronics", 27.99, 150, "2024-01-15"],  # Price changed: 24.99 -> 27.99
    ["P1002", "USB-C Cable", "Accessories", 12.99, 300, "2024-01-18"],
    ["P1003", "Laptop Stand", "Furniture", 49.99, 75, "2024-01-20"],  # Price changed: 45.00 -> 49.99
    ["P1004", "Keyboard", "Electronics", 89.99, 135, "2024-01-22"],  # Quantity changed: 120 -> 135
    ["P1005", "Monitor Arm", "Furniture", 125.00, 45, "2024-01-25"],
    ["P1006", "HD Webcam", "Electronics", 79.99, 90, "2024-01-28"],  # Name changed: "Webcam HD" -> "HD Webcam"
    ["P1007", "Desk Lamp", "Furniture", 34.99, 200, "2024-02-01"],
    ["P1008", "Mouse Pad", "Office Supplies", 9.99, 500, "2024-02-03"],  # Category changed: "Accessories" -> "Office Supplies"
    ["P1009", "HDMI Cable", "Accessories", 17.99, 250, "2024-02-05"],  # Price changed: 15.99 -> 17.99
    ["P1010", "Phone Stand", "Accessories", 18.99, 180, "2024-02-08"]
]

# Track changed cells for verifier (row_idx, col_idx, sheet_name)
# Note: row 0 is header, data starts at row 1
changed_cells = [
    (1, 3),  # P1001 price (row 1, col D=3)
    (3, 3),  # P1003 price (row 3, col D=3)
    (4, 4),  # P1004 quantity (row 4, col E=4)
    (6, 1),  # P1006 name (row 6, col B=1)
    (8, 2),  # P1008 category (row 8, col C=2)
    (9, 3),  # P1009 price (row 9, col D=3)
]

# Save ground truth for verifier
ground_truth = {
    'changed_cells': changed_cells,
    'sheet_name': 'Version 2'
}

with open('/home/ga/Documents/version_comparison_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f)

def create_sheet(doc, sheet_name, data):
    """Create a sheet with the given data"""
    table = Table(name=sheet_name)
    
    for row_data in data:
        row = TableRow()
        for cell_value in row_data:
            cell = TableCell()
            # Handle different data types
            if isinstance(cell_value, (int, float)):
                cell.setAttrNS(None, 'value-type', 'float')
                cell.setAttrNS(None, 'value', str(cell_value))
            else:
                cell.setAttrNS(None, 'value-type', 'string')
            
            # Add text content
            p = P()
            p.addText(str(cell_value))
            cell.addElement(p)
            row.addElement(cell)
        table.addElement(row)
    
    # Add some empty rows for scrolling
    for _ in range(10):
        row = TableRow()
        for _ in range(10):
            cell = TableCell()
            row.addElement(cell)
        table.addElement(row)
    
    doc.spreadsheet.addElement(table)

# Create both sheets
create_sheet(doc, "Version 1", version1_data)
create_sheet(doc, "Version 2", version2_data)

# Save the file
doc.save("/home/ga/Documents/version_comparison.ods")
print("✅ Created version comparison spreadsheet successfully")
print(f"✅ Ground truth saved: {len(changed_cells)} changes between versions")

PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/version_comparison.ods
sudo chown ga:ga /home/ga/Documents/version_comparison_ground_truth.json
sudo chmod 666 /home/ga/Documents/version_comparison.ods
sudo chmod 666 /home/ga/Documents/version_comparison_ground_truth.json

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/version_comparison.ods > /tmp/calc_version_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_version_task.log
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
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

# Navigate to Version 2 sheet (where highlighting should be done)
echo "Navigating to Version 2 sheet..."
safe_xdotool ga :1 key ctrl+Page_Down
sleep 0.5

# Move cursor to top-left
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Version Diff Highlighter Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  • Two sheets: 'Version 1' and 'Version 2' with product data"
echo "  • Compare the data between the two versions"
echo "  • Identify cells in Version 2 that differ from Version 1"
echo "  • Apply background color highlighting to changed cells in Version 2"
echo "  • There are 6 differences to find (prices, quantities, names, categories)"
echo ""
echo "💡 Suggested Approach:"
echo "  1. Switch between sheets using Ctrl+PageUp/PageDown"
echo "  2. Compare data systematically (row by row or column by column)"
echo "  3. Select changed cells in Version 2 and apply background color:"
echo "     - Right-click → Format Cells → Background"
echo "     - Or use Format → Cells → Background tab"
echo "  4. Use any visible color (yellow, red, orange recommended)"
echo "  5. Save the file when complete (Ctrl+S)"