#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Prescription Price Comparison Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DESKTOP_DIR="/home/ga/Desktop"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$DESKTOP_DIR"

# Create the pharmacy quotes text file with realistic messy data
QUOTES_PATH="$DESKTOP_DIR/pharmacy_quotes.txt"

cat > "$QUOTES_PATH" << 'EOF'
PHARMACY PRICE QUOTES - December 2024
=====================================

Called CVS - they said:
- Metformin 500mg (60 tablets per month): $24.99 for 30 days
- Lisinopril 10mg: $18/month
- Atorvastatin 20mg - $33 cash price
- Levothyroxine 50mcg: $19.99

Walgreens prices (with Savings Club membership):
Metformin 500mg - $28.50
Lisinopril 10mg - $15.99
Atorvastatin - $38.00
Levothyroxine 50mcg $22

Costco (requires $60/year membership):
- Metformin 500: $11.99
- Lisinopril: $8.50
- Atorvastatin: $12.00
- Levo: $9.99

GoodRx coupon prices at Kroger Pharmacy:
Metformin: $15
Lisinopril: $12
Atorvastatin: $18
Levothyroxine: $14

Walmart $4 Generic Program:
- Metformin 500mg: $4 (30 day supply)
- Lisinopril 10mg: $4
- Atorvastatin NOT on $4 list - regular price $29
- Levothyroxine: $4

Target/CVS (inside Target store):
Similar to CVS main prices
Metformin: $25
Lisinopril: $18
Atorvastatin: $33
Levothyroxine: $17

NOTES:
- All prices are for 30-day supply unless noted
- Costco membership: $60/year
- GoodRx coupons are free but you need to show them at pharmacy
- Walmart $4 generics require specific dosages/quantities
EOF

chown ga:ga "$QUOTES_PATH"
echo "✅ Pharmacy quotes file created at: $QUOTES_PATH"

# Create a blank spreadsheet
SHEET_PATH="$WORKSPACE_DIR/medication_costs.xlsx"

cat > /tmp/create_med_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Medication Costs"

# Add a simple header to guide the user
ws['A1'] = "Prescription Price Comparison"
ws['A1'].font = Font(size=14, bold=True)

# Add a hint in cell A3
ws['A3'] = "Instructions: Compare prices from pharmacy_quotes.txt and organize them below"
ws['A3'].font = Font(size=10, italic=True)

# Set some column widths for readability
ws.column_dimensions['A'].width = 25
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 15
ws.column_dimensions['F'].width = 15

wb.save(sys.argv[1])
print(f"Spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_med_sheet.py
python3 /tmp/create_med_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_prescription_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_prescription_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

# Also open the text file in a simple text editor for easy reference
echo "Opening pharmacy quotes in text editor..."
su - ga -c "DISPLAY=:1 xdg-open '$QUOTES_PATH' > /tmp/texteditor_task.log 2>&1 &" || true
sleep 2

echo "=== Prescription Price Comparison Task Setup Complete ==="
echo "📝 Scenario:"
echo "  You've been prescribed 4 medications and need to find the cheapest options."
echo "  Price quotes from 6 pharmacies are in: pharmacy_quotes.txt (on Desktop)"
echo ""
echo "📋 Task Requirements:"
echo "  1. Create a comparison table with all 4 medications:"
echo "     - Metformin 500mg"
echo "     - Lisinopril 10mg"
echo "     - Atorvastatin 20mg"
echo "     - Levothyroxine 50mcg"
echo ""
echo "  2. Include prices from at least 5 pharmacy options:"
echo "     - CVS, Walgreens, Costco, Walmart, GoodRx at Kroger"
echo ""
echo "  3. Use formulas to calculate total monthly cost per pharmacy"
echo ""
echo "  4. Make the comparison clear and easy to read"
echo ""
echo "  5. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 Tip: Consider noting Costco membership fee and special programs"