#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Estate Asset Inventory Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw inventory file with disorganized data
RAW_FILE="$WORKSPACE_DIR/estate_inventory_raw.xlsx"

cat > /tmp/create_estate_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Raw Data"

# Disorganized data simulating scattered documents from estate gathering
# No headers, inconsistent structure, liens mentioned in text
raw_data = [
    ["Bank of America Checking", 12450, "", ""],
    ["House - 847 Maple Street", 385000, "mortgage balance 180k", ""],
    ["2019 Honda CR-V", 16500, "car loan $4200 left", ""],
    ["Jewelry (appraised)", 8200, "", ""],
    ["Bank of America Savings", 34670, "", ""],
    ["Fidelity IRA", 127300, "", ""],
    ["Life Insurance Payout", 50000, "", ""],
    ["China cabinet (antique, estimated)", 1200, "not appraised yet", ""],
    ["Credit card debt", -3800, "Capital One", ""],
]

for row_idx, row_data in enumerate(raw_data, start=1):
    for col_idx, value in enumerate(row_data, start=1):
        ws.cell(row=row_idx, column=col_idx, value=value)

wb.save(sys.argv[1])
print(f"Raw estate inventory file created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_estate_sheet.py
python3 /tmp/create_estate_sheet.py "$RAW_FILE"
chown ga:ga "$RAW_FILE"

echo "✅ Raw estate inventory created at: $RAW_FILE"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$RAW_FILE' > /tmp/onlyoffice_estate_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_estate_task.log || true
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

echo "=== Estate Asset Inventory Task Setup Complete ==="
echo "📝 Context: You are the executor of Aunt Marie's estate. She died unexpectedly"
echo "   and left no organized records. The probate court requires a detailed asset"
echo "   inventory in 10 days. You've gathered scattered documents (bank statements,"
echo "   property deeds, appraisals) and created this rough spreadsheet."
echo ""
echo "📋 Your task:"
echo "  1. Transform the disorganized data into a proper estate inventory"
echo "  2. Create columns: Description, Gross Value, Liens/Debts, Net Value, Status, Category"
echo "  3. Add TOTALS section: Total Gross Assets, Total Liens/Debts, Net Estate Value"
echo "  4. Add BENEFICIARY section: 4 beneficiaries, share per beneficiary (Net / 4)"
echo "  5. Use formulas for ALL calculations (net values, totals, shares)"
echo "  6. Apply professional formatting suitable for court filing"
echo "  7. Save the inventory (Ctrl+S)"
echo ""
echo "💡 Key details from gathered documents:"
echo "  - House has $180,000 mortgage balance"
echo "  - Honda has $4,200 car loan remaining"
echo "  - China cabinet value is estimated (not yet appraised)"
echo "  - Credit card debt is owed by the estate"
echo "  - Four beneficiaries will split the net estate equally"