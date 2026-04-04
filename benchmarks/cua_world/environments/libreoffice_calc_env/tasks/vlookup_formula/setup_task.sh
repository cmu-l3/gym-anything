#!/bin/bash
# set -euo pipefail

echo "=== Setting up VLOOKUP Formula task ==="

source /workspace/scripts/task_utils.sh

# Create a temporary Python script to generate multi-sheet ODS
cat > /tmp/create_vlookup_sheets.py << 'PYEOF'
#!/usr/bin/env python3
import sys
try:
    from odf.opendocument import OpenDocumentSpreadsheet
    from odf.table import Table, TableRow, TableCell
    from odf.text import P
except ImportError:
    print("odfpy not available, using CSV fallback")
    sys.exit(1)

# Create new ODS document
doc = OpenDocumentSpreadsheet()

# Create Products sheet
products_table = Table(name="Products")
# Header
header_row = TableRow()
cell1 = TableCell(valuetype="string")
cell1.addElement(P(text="Product ID"))
header_row.addElement(cell1)
cell2 = TableCell(valuetype="string")
cell2.addElement(P(text="Price"))
header_row.addElement(cell2)
products_table.addElement(header_row)

# Data rows
products_data = [
    ("P001", 29.99),
    ("P002", 49.99),
    ("P003", 15.99),
    ("P004", 89.99),
    ("P005", 12.50)
]

for pid, price in products_data:
    row = TableRow()
    cell1 = TableCell(valuetype="string")
    cell1.addElement(P(text=pid))
    row.addElement(cell1)
    cell2 = TableCell(valuetype="float", value=str(price))
    cell2.addElement(P(text=str(price)))
    row.addElement(cell2)
    products_table.addElement(row)

doc.spreadsheet.addElement(products_table)

# Create Orders sheet
orders_table = Table(name="Orders")
# Header
header_row = TableRow()
cell1 = TableCell(valuetype="string")
cell1.addElement(P(text="Order ID"))
header_row.addElement(cell1)
cell2 = TableCell(valuetype="string")
cell2.addElement(P(text="Product ID"))
header_row.addElement(cell2)
cell3 = TableCell(valuetype="string")
cell3.addElement(P(text="Price"))
header_row.addElement(cell3)
orders_table.addElement(header_row)

# Data rows (prices to be filled)
orders_data = [
    ("O001", "P002"),
    ("O002", "P001"),
    ("O003", "P004"),
    ("O004", "P003"),
    ("O005", "P005")
]

for oid, pid in orders_data:
    row = TableRow()
    cell1 = TableCell(valuetype="string")
    cell1.addElement(P(text=oid))
    row.addElement(cell1)
    cell2 = TableCell(valuetype="string")
    cell2.addElement(P(text=pid))
    row.addElement(cell2)
    cell3 = TableCell()  # Empty cell for price
    row.addElement(cell3)
    orders_table.addElement(row)

doc.spreadsheet.addElement(orders_table)

# Save document
doc.save("/home/ga/Documents/vlookup_exercise.ods")
print("Multi-sheet ODS created successfully")
PYEOF

chmod +x /tmp/create_vlookup_sheets.py

# Try to create multi-sheet ODS
python3 /tmp/create_vlookup_sheets.py || {
    echo "odfpy not available, creating CSV fallback"
    
    # Fallback: create two separate CSV files
    cat > /home/ga/Documents/products.csv << 'EOF'
Product ID,Price
P001,29.99
P002,49.99
P003,15.99
P004,89.99
P005,12.50
EOF

    cat > /home/ga/Documents/orders.csv << 'EOF'
Order ID,Product ID,Price
O001,P002,
O002,P001,
O003,P004,
O004,P003,
O005,P005,
EOF
    
    chown ga:ga /home/ga/Documents/*.csv
    
    # Open both CSVs
    su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/products.csv /home/ga/Documents/orders.csv > /tmp/libreoffice_vlookup.log 2>&1 &"
}

# Open the ODS file
if [ -f "/home/ga/Documents/vlookup_exercise.ods" ]; then
    chown ga:ga /home/ga/Documents/vlookup_exercise.ods
    su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/vlookup_exercise.ods > /tmp/libreoffice_vlookup.log 2>&1 &"
fi

sleep 5

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_task.log
    # exit 1
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # exit 1
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


echo "=== VLOOKUP Formula task setup completed ==="
echo "📋 Task: Use VLOOKUP to fill prices in Orders sheet from Products sheet"
echo "💡 Formula: =VLOOKUP(B2,Products.A:B,2,FALSE)"
