#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Medical Bill Reconciliation Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create Bills CSV with intentional duplicates and issues
cat > /home/ga/Documents/sample_bills.csv << 'EOF'
Bill Date,Provider,Date of Service,Procedure,Amount Billed
2024-01-15,City Hospital,2024-01-02,Emergency Room Visit,850.00
2024-01-18,Dr. Sarah Chen,2024-01-02,Emergency Physician Services,425.00
2024-01-20,CITY HOSPITAL,2024-01-02,Emergency Room Visit,850.00
2024-01-22,Radiology Associates,2024-01-02,X-Ray Chest 2 Views,180.00
2024-01-25,Pathology Labs Inc,2024-01-02,Blood Work Panel,95.00
2024-01-28,Dr. Sarah Chen,2024-01-02,ER Physician Services,425.00
2024-02-01,City Hospital,2024-01-05,Follow-up Office Visit,200.00
2024-02-03,Pharmacy Benefit Mgr,2024-01-06,Prescription Antibiotics,45.00
EOF

# Create EOB (Explanation of Benefits) CSV
cat > /home/ga/Documents/sample_eob.csv << 'EOF'
Claim Date,Provider,Procedure Code,Amount Charged,Insurance Paid,Patient Responsibility
2024-01-10,City Hospital,99285,850.00,680.00,170.00
2024-01-10,Chen Sarah MD,99285,425.00,340.00,85.00
2024-01-12,Radiology Assoc,71020,180.00,144.00,36.00
2024-01-12,Pathology Labs,80053,95.00,95.00,0.00
2024-01-15,City Hospital,99213,200.00,160.00,40.00
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/sample_bills.csv
sudo chown ga:ga /home/ga/Documents/sample_eob.csv

# Install python-odf if not already installed
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing python-odf..."
    sudo apt-get update && sudo apt-get install -y python3-odf
fi

# Create ODS workbook with two sheets using Python
python3 << 'PYEOF'
import csv
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

def csv_to_sheet(doc, sheet_name, csv_path):
    """Convert CSV to ODS sheet"""
    table = Table(name=sheet_name)
    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        for row_data in reader:
            row = TableRow()
            for cell_value in row_data:
                cell = TableCell()
                cell.addElement(P(text=cell_value))
                row.addElement(cell)
            table.addElement(row)
    doc.spreadsheet.addElement(table)

# Create new spreadsheet document
doc = OpenDocumentSpreadsheet()

# Add Bills sheet
csv_to_sheet(doc, "Bills", "/home/ga/Documents/sample_bills.csv")

# Add EOB sheet
csv_to_sheet(doc, "EOB", "/home/ga/Documents/sample_eob.csv")

# Save combined workbook
doc.save("/home/ga/Documents/medical_bills.ods")
print("✅ Created medical_bills.ods with Bills and EOB sheets")
PYEOF

# Set correct permissions on ODS file
sudo chown ga:ga /home/ga/Documents/medical_bills.ods
sudo chmod 666 /home/ga/Documents/medical_bills.ods

# Launch LibreOffice Calc with the workbook
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/medical_bills.ods > /tmp/calc_medbill_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_medbill_task.log || true
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

# Ensure we're on the Bills sheet (first sheet)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Medical Bill Reconciliation Task Setup Complete ==="
echo "📋 Workbook ready with Bills and EOB sheets"
echo ""
echo "📝 Instructions:"
echo "  1. Review the Bills sheet (current) and EOB sheet (second tab)"
echo "  2. Add columns: 'Discrepancy', 'Status', and optionally 'EOB Match'"
echo "  3. Use VLOOKUP or INDEX-MATCH to match bills to EOB entries"
echo "  4. Identify duplicates (same provider + date + procedure)"
echo "  5. Calculate discrepancies: Billed Amount - EOB Patient Responsibility"
echo "  6. Flag issues: DUPLICATE, DISPUTE (if discrepancy >$10), OK, NOT IN EOB"
echo "  7. Apply conditional formatting to Status column"
echo "  8. Create summary: Total Billed, Total Owed, Total Overage"
echo ""
echo "💡 Hints:"
echo "  - Provider names may not match exactly (e.g., 'City Hospital' vs 'CITY HOSPITAL')"
echo "  - Look for duplicate bills on rows 1 vs 3, and rows 2 vs 6"
echo "  - Pharmacy bill (row 8) has no EOB entry"