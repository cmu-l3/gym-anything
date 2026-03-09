#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Professional Certification Renewal Manager Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with realistic certification data
# Mix of expired, urgent, current, and future certifications
cat > /home/ga/Documents/certifications_data.csv << 'EOF'
Certification Name,Issuing Body,Expiration Date,Renewal Cost,CE Credits Required,CE Credits Completed
Registered Nurse License,State Board of Nursing,2024-03-15,150,30,30
BLS Certification,American Heart Association,2024-06-20,75,4,4
ACLS Certification,American Heart Association,2024-01-10,180,8,5
Pediatric Advanced Life Support,American Heart Association,2025-08-30,200,8,8
Wound Care Specialist,WOCN,2024-04-05,350,15,12
Clinical Nurse Specialist,ANCC,2026-12-15,395,75,45
IV Therapy Certification,INS,2024-02-28,125,10,10
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/certifications_data.csv
sudo chmod 666 /home/ga/Documents/certifications_data.csv

echo "✅ Created certifications_data.csv with sample data"

# Convert CSV to ODS using headless LibreOffice
echo "Converting CSV to ODS format..."
su - ga -c "DISPLAY=:1 libreoffice --headless --convert-to ods --outdir /home/ga/Documents /home/ga/Documents/certifications_data.csv > /tmp/csv_convert.log 2>&1" || true
sleep 2

# Check if conversion succeeded, if not create manually with Python
if [ ! -f "/home/ga/Documents/certifications_data.ods" ]; then
    echo "CSV conversion failed, creating ODS directly with Python..."
    
    # Ensure odfpy is installed
    python3 -c "import odf" 2>/dev/null || pip3 install -q odfpy
    
    python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, TableCellProperties
from odf.number import NumberStyle, Number, CurrencyStyle, CurrencySymbol, Text as NumberText, DateStyle, Day, Month, Year

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Sheet1"
table = Table(name="Sheet1")
doc.spreadsheet.addElement(table)

# Data
headers = ["Certification Name", "Issuing Body", "Expiration Date", "Renewal Cost", "CE Credits Required", "CE Credits Completed"]
data = [
    ["Registered Nurse License", "State Board of Nursing", "2024-03-15", 150, 30, 30],
    ["BLS Certification", "American Heart Association", "2024-06-20", 75, 4, 4],
    ["ACLS Certification", "American Heart Association", "2024-01-10", 180, 8, 5],
    ["Pediatric Advanced Life Support", "American Heart Association", "2025-08-30", 200, 8, 8],
    ["Wound Care Specialist", "WOCN", "2024-04-05", 350, 15, 12],
    ["Clinical Nurse Specialist", "ANCC", "2026-12-15", 395, 75, 45],
    ["IV Therapy Certification", "INS", "2024-02-28", 125, 10, 10],
]

# Add header row
header_row = TableRow()
for header in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
table.addElement(header_row)

# Add data rows
for row_data in data:
    row = TableRow()
    for i, value in enumerate(row_data):
        if i == 2:  # Date column
            cell = TableCell(valuetype="date", datevalue=value)
            cell.addElement(P(text=value))
        elif i == 3:  # Currency column
            cell = TableCell(valuetype="float", value=str(value))
            cell.addElement(P(text=f"${value}"))
        elif isinstance(value, (int, float)):
            cell = TableCell(valuetype="float", value=str(value))
            cell.addElement(P(text=str(value)))
        else:
            cell = TableCell(valuetype="string")
            cell.addElement(P(text=str(value)))
        row.addElement(cell)
    table.addElement(row)

# Add some empty rows for workspace
for _ in range(15):
    row = TableRow()
    for _ in range(12):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/certifications_data.ods")
print("✅ Created ODS file successfully")
PYEOF
    
    # Set permissions
    sudo chown ga:ga /home/ga/Documents/certifications_data.ods
    sudo chmod 666 /home/ga/Documents/certifications_data.ods
fi

# Rename to working filename
cp /home/ga/Documents/certifications_data.ods /home/ga/Documents/certification_tracker.ods
sudo chown ga:ga /home/ga/Documents/certification_tracker.ods
sudo chmod 666 /home/ga/Documents/certification_tracker.ods

echo "✅ Certification tracking spreadsheet ready"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/certification_tracker.ods > /tmp/calc_cert_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "⚠️  WARNING: LibreOffice process not detected (may already be running)"
    cat /tmp/calc_cert_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "⚠️  WARNING: LibreOffice Calc window not detected"
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 640 400 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        echo "✅ Calc window focused"
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
else
    echo "⚠️  Could not get Calc window ID, attempting alternative focus..."
    su - ga -c "DISPLAY=:1 wmctrl -a 'LibreOffice Calc'" || true
    sleep 1
fi

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Professional Certification Renewal Manager Task Setup Complete ==="
echo ""
echo "📋 Task Overview:"
echo "  Transform this certification list into a compliance dashboard with:"
echo ""
echo "📝 Required Actions:"
echo "  1. Add 'Days Until Expiration' column (G) with formula: =C2-TODAY()"
echo "  2. Add 'Status' column (H) with nested IF for EXPIRED/URGENT/CURRENT/FUTURE"
echo "  3. Apply red conditional formatting to URGENT and EXPIRED statuses"
echo "  4. Add SUM formula for total renewal costs"
echo "  5. Add 'CE Status' column (I) comparing completed vs required CE credits"
echo "  6. Apply yellow formatting to INCOMPLETE CE status"
echo "  7. Sort entire data by Days Until Expiration (ascending)"
echo ""
echo "💡 Key Skills:"
echo "  - TODAY() function for current date"
echo "  - Nested IF: =IF(G2<0,\"EXPIRED\",IF(G2<90,\"URGENT\",IF(G2<365,\"CURRENT\",\"FUTURE\")))"
echo "  - Conditional formatting for visual alerts"
echo "  - SUM for financial aggregation"
echo "  - Data sorting while maintaining row integrity"
echo ""
echo "🎯 Success Criteria: 6 out of 8 criteria (75%)"