#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Equipment Rental Coordinator Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$DOCS_DIR"

# Create the input data file with rental bookings
INPUT_FILE="$DOCS_DIR/rental_bookings.txt"

cat > "$INPUT_FILE" << 'EOF'
UPCOMING EQUIPMENT RENTALS - COMMUNITY MAKERSPACE

Item: Projector
Renter: Alice Chen
Rental period: March 15-17, 2025
Deposit paid: $60
Equipment value: $300

Item: PA Sound System
Renter: Bob Martinez
Rental period: March 16-18, 2025
Deposit paid: $100
Equipment value: $500

Item: Folding Tables (set of 10)
Renter: Alice Chen
Rental period: March 15-17, 2025
Deposit paid: $40
Equipment value: $200

Item: Projector
Renter: Dana Kim
Rental period: March 18-20, 2025
Deposit paid: $60
Equipment value: $300

Item: PA Sound System
Renter: Elena Rodriguez
Rental period: March 17-19, 2025
Deposit paid: $100
Equipment value: $500
CONFLICT: Overlaps with Bob Martinez booking!

Item: Folding Tables (set of 10)
Renter: Frank Thompson
Rental period: March 19-21, 2025
Deposit paid: $40
Equipment value: $200

POLICY NOTES:
- Deposit = 20% of equipment value
- Late fee = $15 per day past return date
- Damaged equipment: deduct repair cost from deposit
- If returned in perfect condition: full deposit refund
- IMPORTANT: Elena Rodriguez's PA System rental (March 17-19) 
  conflicts with Bob Martinez's rental (March 16-18)
EOF

chown ga:ga "$INPUT_FILE"

echo "✅ Input data file created at: $INPUT_FILE"

# Create the initial blank spreadsheet for the task
SHEET_PATH="$WORKSPACE_DIR/equipment_rental_tracker.xlsx"

cat > /tmp/create_rental_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
import sys

wb = Workbook()
ws = wb.active
ws.title = "Rental Tracker"

# Add headers with formatting
headers = [
    "Item Name",
    "Renter Name", 
    "Start Date",
    "End Date",
    "Deposit Paid",
    "Equipment Value",
    "Status",
    "Days Rented",
    "Late Days",
    "Late Fee",
    "Condition on Return",
    "Deposit Refund",
    "Conflict?"
]

# Apply header formatting
header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")
header_font = Font(bold=True, color="FFFFFF", size=11)
thin_border = Border(
    left=Side(style='thin'),
    right=Side(style='thin'),
    top=Side(style='thin'),
    bottom=Side(style='thin')
)

for idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=idx, value=header)
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal='center', vertical='center')
    cell.border = thin_border

# Set column widths for readability
ws.column_dimensions['A'].width = 25  # Item Name
ws.column_dimensions['B'].width = 18  # Renter Name
ws.column_dimensions['C'].width = 12  # Start Date
ws.column_dimensions['D'].width = 12  # End Date
ws.column_dimensions['E'].width = 13  # Deposit Paid
ws.column_dimensions['F'].width = 15  # Equipment Value
ws.column_dimensions['G'].width = 12  # Status
ws.column_dimensions['H'].width = 12  # Days Rented
ws.column_dimensions['I'].width = 10  # Late Days
ws.column_dimensions['J'].width = 10  # Late Fee
ws.column_dimensions['K'].width = 18  # Condition
ws.column_dimensions['L'].width = 14  # Deposit Refund
ws.column_dimensions['M'].width = 10  # Conflict

# Add instruction note
ws['A15'] = "INSTRUCTIONS:"
ws['A16'] = "1. Read rental data from /home/ga/Documents/rental_bookings.txt"
ws['A17'] = "2. Enter all 6 rental bookings in rows 2-7"
ws['A18'] = "3. Calculate Days Rented (End Date - Start Date + 1)"
ws['A19'] = "4. Identify CONFLICT: Elena Rodriguez & Bob Martinez both have PA System"
ws['A20'] = "5. Apply conditional formatting to highlight conflicts"

instruction_font = Font(italic=True, color="666666", size=9)
for row in range(15, 21):
    ws[f'A{row}'].font = instruction_font

wb.save(sys.argv[1])
print(f"Rental tracking spreadsheet template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_rental_sheet.py
python3 /tmp/create_rental_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet template created at: $SHEET_PATH"

# Open the input text file in gedit for easy reference
echo "Opening input file for reference..."
su - ga -c "DISPLAY=:1 gedit '$INPUT_FILE' > /tmp/gedit_rental.log 2>&1 &"
sleep 2

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_rental_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_rental_task.log || true
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

echo "=== Equipment Rental Coordinator Task Setup Complete ==="
echo ""
echo "📋 TASK OVERVIEW:"
echo "  Community Makerspace Equipment Rental Tracking"
echo ""
echo "📝 YOUR MISSION:"
echo "  Create a rental schedule that prevents double-bookings and calculates deposits"
echo ""
echo "📄 INPUT DATA:"
echo "  /home/ga/Documents/rental_bookings.txt"
echo "  (Also open in text editor for reference)"
echo ""
echo "✅ REQUIREMENTS:"
echo "  1. Enter all 6 rental bookings from the text file"
echo "  2. Use proper date format (e.g., 3/15/2025 or 2025-03-15)"
echo "  3. Calculate 'Days Rented' = End Date - Start Date + 1"
echo "  4. CRITICAL: Identify the CONFLICT!"
echo "     - Bob Martinez: PA System, March 16-18"
echo "     - Elena Rodriguez: PA System, March 17-19"
echo "     - Mark BOTH as 'YES' or 'CONFLICT' in Conflict column"
echo "  5. Apply appropriate formatting (bold headers, borders, etc.)"
echo "  6. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 RENTAL DATA SUMMARY:"
echo "  • Projector: Alice Chen (Mar 15-17), Dana Kim (Mar 18-20)"
echo "  • PA System: Bob Martinez (Mar 16-18), Elena Rodriguez (Mar 17-19) ⚠️ CONFLICT"
echo "  • Tables: Alice Chen (Mar 15-17), Frank Thompson (Mar 19-21)"
echo ""
echo "🎯 SUCCESS CRITERIA:"
echo "  - All 6 rentals entered correctly"
echo "  - Deposits match 20% rule (Projector=$60, PA=$100, Tables=$40)"
echo "  - PA System conflict correctly flagged"
echo "  - Professional spreadsheet formatting"