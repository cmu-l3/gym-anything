#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Subscription Audit Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with headers only
SHEET_PATH="$WORKSPACE_DIR/subscription_audit.xlsx"

cat > /tmp/create_subscription_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "Subscription Audit"

# Add headers with formatting
headers = [
    "Service Name",
    "Category", 
    "Billing Cycle",
    "Charged Amount",
    "Monthly Cost",
    "Usage Value",
    "Annual Savings if Canceled"
]

header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
header_font = Font(bold=True, color="FFFFFF")

for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal="center", vertical="center")

# Set column widths for better readability
ws.column_dimensions['A'].width = 25  # Service Name
ws.column_dimensions['B'].width = 15  # Category
ws.column_dimensions['C'].width = 15  # Billing Cycle
ws.column_dimensions['D'].width = 15  # Charged Amount
ws.column_dimensions['E'].width = 15  # Monthly Cost
ws.column_dimensions['F'].width = 15  # Usage Value
ws.column_dimensions['G'].width = 25  # Annual Savings

# Add helpful instruction comment in A2
ws['A2'] = "Enter at least 6 subscriptions below"
instruction_font = Font(italic=True, color="666666")
ws['A2'].font = instruction_font

# Add example billing cycles as a comment/note in C2
ws['C2'] = "Monthly/Annual/Quarterly/Weekly"
ws['C2'].font = instruction_font

# Add example usage values in F2
ws['F2'] = "High/Medium/Low"
ws['F2'].font = instruction_font

wb.save(sys.argv[1])
print(f"Subscription audit spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_subscription_sheet.py
python3 /tmp/create_subscription_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Subscription audit spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_subscription_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_subscription_task.log || true
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

echo "=== Subscription Audit Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Enter at least 6 subscriptions with all required fields"
echo "  2. Example subscriptions: Netflix, Amazon Prime, Gym, Adobe, Spotify, etc."
echo "  3. Billing Cycle: Monthly, Annual, Quarterly, or Weekly"
echo "  4. Usage Value: High, Medium, or Low"
echo "  5. Create Monthly Cost formulas to normalize billing cycles:"
echo "     - Monthly: use as-is"
echo "     - Annual: divide by 12"
echo "     - Quarterly: divide by 3"
echo "     - Weekly: multiply by 4.33"
echo "  6. Create Annual Savings formulas: Monthly Cost × 12"
echo "  7. Add summary row: Total Potential Savings for Low value items (use SUMIF)"
echo "  8. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Example formula for Monthly Cost (row 3): =IF(C3=\"Monthly\",D3,IF(C3=\"Annual\",D3/12,IF(C3=\"Quarterly\",D3/3,IF(C3=\"Weekly\",D3*4.33,D3))))"
echo "Example formula for Annual Savings (row 3): =E3*12"
echo "Example SUMIF for total: =SUMIF(F3:F8,\"Low\",G3:G8)"