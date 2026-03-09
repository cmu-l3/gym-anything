#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Medical Bill Reconciliation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with hospital bill data
SHEET_PATH="$WORKSPACE_DIR/hospital_bill_raw.xlsx"

cat > /tmp/create_medical_bill.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
import sys

wb = Workbook()

# Remove default sheet
if 'Sheet' in wb.sheetnames:
    del wb['Sheet']

# ============================================================================
# Sheet 1: Hospital_Charges (from hospital bill)
# ============================================================================
ws1 = wb.create_sheet("Hospital_Charges", 0)

# Headers
headers1 = ["Date", "Service_Code", "Description", "Qty", "Billed_Amount"]
for col_num, header in enumerate(headers1, start=1):
    cell = ws1.cell(row=1, column=col_num)
    cell.value = header
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")

# Hospital charges data (includes duplicates and conflicts)
hospital_data = [
    ["03/15/2024", "99284", "ER Visit Level 4", 1, 875.00],
    ["03/15/2024", "70450", "CT Head w/o contrast", 1, 1250.00],
    ["03/15/2024", "36415", "Venipuncture", 1, 45.00],
    ["03/15/2024", "85025", "Complete Blood Count", 1, 89.00],
    ["03/15/2024", "80053", "Metabolic Panel", 1, 112.00],
    ["03/15/2024", "36415", "Routine venipuncture", 1, 45.00],  # DUPLICATE
    ["03/15/2024", "J2250", "Injection, midazolam", 2, 78.00],
    ["03/15/2024", "99285", "ER Visit Level 5", 1, 1124.00],  # CONFLICT - wrong level
    ["03/15/2024", "70470", "CT Head w/ contrast", 1, 229.00],  # NOT ORDERED
]

for row_num, row_data in enumerate(hospital_data, start=2):
    for col_num, value in enumerate(row_data, start=1):
        ws1.cell(row=row_num, column=col_num, value=value)

# Adjust column widths
ws1.column_dimensions['A'].width = 12
ws1.column_dimensions['B'].width = 13
ws1.column_dimensions['C'].width = 25
ws1.column_dimensions['D'].width = 5
ws1.column_dimensions['E'].width = 14

# ============================================================================
# Sheet 2: Insurance_EOB (from insurance company)
# ============================================================================
ws2 = wb.create_sheet("Insurance_EOB", 1)

# Headers
headers2 = ["Service_Code", "Description", "Billed", "Allowed", "Paid_by_Ins", "Patient_Resp", "Reason"]
for col_num, header in enumerate(headers2, start=1):
    cell = ws2.cell(row=1, column=col_num)
    cell.value = header
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")

# Insurance EOB data
eob_data = [
    ["99284", "ER Visit", 875.00, 625.00, 500.00, 125.00, "Deductible"],
    ["70450", "CT Scan Head", 1250.00, 890.00, 712.00, 178.00, "Copay"],
    ["36415", "Blood Draw", 45.00, 18.00, 18.00, 0.00, "Covered"],
    ["85025", "Blood Count", 89.00, 42.00, 42.00, 0.00, "Covered"],
    ["80053", "Metabolic Panel", 112.00, 56.00, 56.00, 0.00, "Covered"],
    ["J2250", "Medication", 78.00, 78.00, 0.00, 78.00, "Not Covered"],
    ["99285", "ER Visit Level 5", 1124.00, 0.00, 0.00, 0.00, "DENIED - Duplicate"],
    ["70470", "CT with contrast", 229.00, 0.00, 0.00, 0.00, "DENIED - Not ordered"],
]

for row_num, row_data in enumerate(eob_data, start=2):
    for col_num, value in enumerate(row_data, start=1):
        ws2.cell(row=row_num, column=col_num, value=value)

# Adjust column widths
ws2.column_dimensions['A'].width = 13
ws2.column_dimensions['B'].width = 20
ws2.column_dimensions['C'].width = 10
ws2.column_dimensions['D'].width = 10
ws2.column_dimensions['E'].width = 12
ws2.column_dimensions['F'].width = 13
ws2.column_dimensions['G'].width = 20

# Add instructions sheet
ws_inst = wb.create_sheet("Instructions", 2)
ws_inst['A1'] = "TASK: Medical Bill Reconciliation"
ws_inst['A1'].font = Font(bold=True, size=14)

instructions = [
    "",
    "SCENARIO:",
    "You received a $3,847 hospital bill for an ER visit. Insurance sent an EOB (Explanation of Benefits).",
    "The amounts don't match and there are errors. You need to figure out what you ACTUALLY owe.",
    "",
    "YOUR TASK:",
    "1. Create a new sheet called 'Reconciliation'",
    "2. Compare Hospital_Charges sheet with Insurance_EOB sheet",
    "3. Identify and flag:",
    "   - DUPLICATE charges (hint: code 36415 appears twice)",
    "   - DENIED claims (insurance rejected them)",
    "   - DISPUTE items (hospital charged but insurance denied)",
    "   - LEGIT charges (what you actually owe)",
    "4. Create summary calculations:",
    "   - Total amount you should pay (LEGIT items only) - should be ~$381",
    "   - Total disputed amount (can negotiate) - should be ~$1,398+",
    "5. Use FORMULAS (SUM, SUMIF) for calculations, not manual values",
    "6. Save the file (Ctrl+S)",
    "",
    "HINTS:",
    "- Service code 36415 appears TWICE in hospital bill (duplicate)",
    "- Service codes 99285 and 70470 were DENIED by insurance",
    "- Your actual responsibility: $125 (ER deductible) + $178 (CT copay) + $78 (medication) = $381",
]

for row_num, text in enumerate(instructions, start=1):
    ws_inst.cell(row=row_num, column=1, value=text)

ws_inst.column_dimensions['A'].width = 90

# Save workbook
wb.save(sys.argv[1])
print(f"Medical bill spreadsheet created: {sys.argv[1]}")
print(f"- Sheet 1: Hospital_Charges ({len(hospital_data)} items)")
print(f"- Sheet 2: Insurance_EOB ({len(eob_data)} items)")
print(f"- Sheet 3: Instructions")
PYEOF

chmod +x /tmp/create_medical_bill.py
python3 /tmp/create_medical_bill.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Medical bill spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_medbill_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_medbill_task.log || true
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

echo "=== Medical Bill Reconciliation Task Setup Complete ==="
echo ""
echo "📊 SCENARIO:"
echo "  You received a $3,847 hospital bill for an ER visit."
echo "  Insurance sent an EOB but amounts don't match."
echo "  There are duplicate charges and denied claims."
echo ""
echo "📝 YOUR TASK:"
echo "  1. Create a new sheet: 'Reconciliation'"
echo "  2. Compare Hospital_Charges vs Insurance_EOB"
echo "  3. Flag each item:"
echo "     - DUPLICATE (code 36415 appears twice)"
echo "     - DENIED (codes 99285, 70470 rejected by insurance)"
echo "     - DISPUTE (questionable charges)"
echo "     - LEGIT (what you actually owe)"
echo "  4. Add summary formulas:"
echo "     - Amount you should pay: ~$381"
echo "     - Disputed amount: ~$1,398"
echo "  5. Save file (Ctrl+S)"
echo ""
echo "💡 HINT: Check the 'Instructions' sheet for details"