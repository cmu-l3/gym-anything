#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Package Dispute Organizer Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with column headers to guide the agent
SHEET_PATH="$WORKSPACE_DIR/package_disputes.xlsx"

cat > /tmp/create_dispute_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "Package Disputes"

# Add header row with suggested columns
headers = [
    "Item Name",
    "Tracking Number", 
    "Carrier",
    "Order Date",
    "Delivery Date",
    "Issue Type",
    "Policy Days",
    "Claim Deadline",
    "Days Until Deadline",
    "Refund Amount",
    "Priority Flag",
    "Photo Taken?",
    "Tracking Screenshot?",
    "Seller Contacted?",
    "Notes"
]

# Style the header row
header_fill = PatternFill(start_color="CCE5FF", end_color="CCE5FF", fill_type="solid")
header_font = Font(bold=True)

for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal='center', vertical='center')

# Set column widths for better readability
ws.column_dimensions['A'].width = 18  # Item Name
ws.column_dimensions['B'].width = 15  # Tracking
ws.column_dimensions['C'].width = 12  # Carrier
ws.column_dimensions['D'].width = 12  # Order Date
ws.column_dimensions['E'].width = 13  # Delivery Date
ws.column_dimensions['F'].width = 15  # Issue Type
ws.column_dimensions['G'].width = 11  # Policy Days
ws.column_dimensions['H'].width = 13  # Claim Deadline
ws.column_dimensions['I'].width = 13  # Days Until Deadline
ws.column_dimensions['J'].width = 13  # Refund Amount
ws.column_dimensions['K'].width = 13  # Priority Flag
ws.column_dimensions['L'].width = 13  # Photo Taken
ws.column_dimensions['M'].width = 18  # Screenshot
ws.column_dimensions['N'].width = 16  # Seller Contacted
ws.column_dimensions['O'].width = 20  # Notes

# Add instruction comment in cell A2
ws['A2'] = "Enter package information below (6 packages total)"
ws['A2'].font = Font(italic=True, color="666666")

# Add a note about today's date at the top
ws['A9'] = "Today's Date:"
ws['B9'] = "December 5, 2024"
ws['A9'].font = Font(bold=True)

ws['A10'] = "Job Start Date:"
ws['B10'] = "December 12, 2024"
ws['A10'].font = Font(bold=True)

# Add total refund label placeholder at the bottom (agent will fill)
ws['I12'] = "Total Potential Refund:"
ws['J12'] = "[Formula here]"
ws['I12'].font = Font(bold=True)

wb.save(sys.argv[1])
print(f"Package dispute tracker spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_dispute_sheet.py
python3 /tmp/create_dispute_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_dispute_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_dispute_task.log || true
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

echo "=== Package Dispute Organizer Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Create a package dispute tracker with the following information:"
echo ""
echo "  Package 1: Monitor (27\") - Cracked on arrival"
echo "    - Ordered: Nov 24 | Carrier: FedEx | Tracking: FDX7723891"
echo "    - Cost: \$289 | Policy: 30-day return"
echo ""
echo "  Package 2: Desk Chair - Never received (marked delivered Dec 1)"
echo "    - Carrier: UPS | Tracking: TRK9384756"
echo "    - Cost: \$245 | Policy: 14-day claim window"
echo ""
echo "  Package 3: Desk Lamp - Stuck in transit since Nov 28"
echo "    - Carrier: USPS | Tracking: 9400123456"
echo "    - Cost: \$67 | Policy: 30-day delivery guarantee"
echo ""
echo "  Package 4: Webcam - Empty box (opened Dec 3)"
echo "    - Carrier: Amazon Logistics | Tracking: TBA9876543"
echo "    - Cost: \$124 | Policy: 30-day return"
echo ""
echo "  Package 5: Cable Organizer - Arrived fine (NO ISSUE)"
echo ""
echo "  Package 6: Office Supplies - Wrong items shipped"
echo "    - Carrier: FedEx | Tracking: FDX8829341"
echo "    - Cost: \$43 | Policy: 60-day return"
echo ""
echo "  Today: December 5, 2024 | Job starts: December 12, 2024"
echo ""
echo "  Required:"
echo "  - Calculate claim deadline dates based on order dates + policy days"
echo "  - Create formula for 'Days Until Deadline' (deadline - today)"
echo "  - Flag items as URGENT if <7 days until deadline AND value >\$100"
echo "  - Add evidence checklist columns (Photo? Screenshot? Contacted?)"
echo "  - Calculate total potential refund (sum of items WITH issues)"
echo "  - Save the spreadsheet (Ctrl+S)"