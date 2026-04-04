#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Band Gig Manager Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with three sheets and headers
SHEET_PATH="$WORKSPACE_DIR/band_manager.xlsx"

cat > /tmp/create_band_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()

# ========== Sheet 1: Gig Log ==========
ws_gig = wb.active
ws_gig.title = "Gig Log"

# Add headers with formatting
headers_gig = ["Date", "Venue Name", "Total Payment", "Guitarist", "Bassist", "Drummer", "Vocalist", "Duration (min)", "Notes"]
for col_idx, header in enumerate(headers_gig, start=1):
    cell = ws_gig.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")

# Add instruction row
ws_gig['A2'] = "Example: 2024-03-15"
ws_gig['B2'] = "The Blue Note"
ws_gig['C2'] = 600
ws_gig['D2'] = "=C2/4"
ws_gig['E2'] = "=C2/4"
ws_gig['F2'] = "=C2/4"
ws_gig['G2'] = "=C2/4"
ws_gig['H2'] = 90
ws_gig['I2'] = "Great crowd, requested encore"

# Add note about totals
ws_gig['A9'] = "TOTAL EARNINGS:"
ws_gig.cell(row=9, column=1).font = Font(bold=True)
ws_gig['D9'] = "=SUM(D2:D8)"
ws_gig['E9'] = "=SUM(E2:E8)"
ws_gig['F9'] = "=SUM(F2:F8)"
ws_gig['G9'] = "=SUM(G2:G8)"

# Set column widths
ws_gig.column_dimensions['A'].width = 15
ws_gig.column_dimensions['B'].width = 20
ws_gig.column_dimensions['C'].width = 15
ws_gig.column_dimensions['D'].width = 12
ws_gig.column_dimensions['E'].width = 12
ws_gig.column_dimensions['F'].width = 12
ws_gig.column_dimensions['G'].width = 12
ws_gig.column_dimensions['H'].width = 15
ws_gig.column_dimensions['I'].width = 30

# ========== Sheet 2: Equipment ==========
ws_equip = wb.create_sheet("Equipment")

headers_equip = ["Item Name", "Owner", "Purchase Date", "Warranty Expiration", "Last Maintenance", "Maintenance Due", "Replacement Cost"]
for col_idx, header in enumerate(headers_equip, start=1):
    cell = ws_equip.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")

# Add example row
ws_equip['A2'] = "PA System (Yamaha)"
ws_equip['B2'] = "Guitarist"
ws_equip['C2'] = "2023-06-01"
ws_equip['D2'] = "2025-06-01"
ws_equip['E2'] = "2024-09-15"
ws_equip['F2'] = "=EDATE(E2,6)"
ws_equip['G2'] = 1200

# Set column widths
ws_equip.column_dimensions['A'].width = 20
ws_equip.column_dimensions['B'].width = 15
ws_equip.column_dimensions['C'].width = 15
ws_equip.column_dimensions['D'].width = 18
ws_equip.column_dimensions['E'].width = 18
ws_equip.column_dimensions['F'].width = 18
ws_equip.column_dimensions['G'].width = 18

# ========== Sheet 3: Set Lists ==========
ws_setlist = wb.create_sheet("Set Lists")

headers_setlist = ["Set List Name", "Songs (comma-separated)", "Total Duration (min)", "Notes/Venue Type"]
for col_idx, header in enumerate(headers_setlist, start=1):
    cell = ws_setlist.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")

# Add example
ws_setlist['A2'] = "Bar Gigs Standard"
ws_setlist['B2'] = "Sweet Child O' Mine, Livin' on a Prayer, Don't Stop Believin', Brown Eyed Girl, Wonderwall, Mr. Brightside, Sweet Caroline, Wagon Wheel"
ws_setlist['C2'] = 75
ws_setlist['D2'] = "Works well for casual bar crowds, high energy"

# Set column widths
ws_setlist.column_dimensions['A'].width = 20
ws_setlist.column_dimensions['B'].width = 50
ws_setlist.column_dimensions['C'].width = 20
ws_setlist.column_dimensions['D'].width = 35

# Save workbook
wb.save(sys.argv[1])
print(f"Band management spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_band_sheet.py
python3 /tmp/create_band_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Band management spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_band_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_band_task.log || true
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

echo "=== Band Gig Manager Task Setup Complete ==="
echo ""
echo "📝 TASK SCENARIO:"
echo "You play guitar in a local cover band. After 6 months of informal gigs,"
echo "band members are arguing about payments and forgetting important details."
echo "Create a management spreadsheet to prevent the band from falling apart!"
echo ""
echo "✅ REQUIREMENTS:"
echo ""
echo "📊 Sheet 1: 'Gig Log' (track at least 4 gigs)"
echo "   - Date, Venue Name, Total Payment"
echo "   - Payment per member (4 members) calculated with FORMULAS (divide total by 4)"
echo "   - Set duration and notes"
echo "   - Add a row at bottom with TOTAL EARNINGS per member using SUM formulas"
echo ""
echo "🎸 Sheet 2: 'Equipment' (inventory at least 5 items)"
echo "   - Item name, Owner, Purchase date, Warranty expiration"
echo "   - Last maintenance date, Maintenance due date (FORMULA: 6 months after last)"
echo "   - Estimated replacement cost"
echo ""
echo "🎵 Sheet 3: 'Set Lists' (create at least 3 different sets)"
echo "   - Set list name (e.g., 'Wedding Set A', 'Bar Gigs Standard')"
echo "   - Songs included (list 8+ songs per set, comma-separated is fine)"
echo "   - Total duration estimate"
echo "   - Notes on audience type or venues"
echo ""
echo "💾 Save as: /home/ga/Documents/Spreadsheets/band_manager.xlsx"
echo ""
echo "NOTE: Example rows are provided as reference - you need to add MORE data!"
echo "      Delete example rows if needed, or add below them."