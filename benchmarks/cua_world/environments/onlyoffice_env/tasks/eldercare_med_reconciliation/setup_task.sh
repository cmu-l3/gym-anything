#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Eldercare Medication Reconciliation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy receipt text file
TEXT_PATH="$WORKSPACE_DIR/med_receipts_november.txt"

cat > "$TEXT_PATH" << 'EOF'
november med receipts

11/3 - Mike picked up from Walgreens - Mom's metformin 1000mg (90 day supply) - $47.82

Nov 8th Sarah got the Amlodipine 5mg at CVS, insurance didn't cover it this time??? $89.50

11/12 I (you) grabbed the atorvastatin from the CVS by my office, 30 day - copay was $15

Walgreens 11/15 - Mike - Omeprazole 20mg (OTC recommendation from Dr. Patel) $18.99

November 19 - Sarah - mail order pharmacy - 90 day Levothyroxine 50mcg - $12.00 (finally insurance worked)

11/23 - Me - CVS - Emergency refill of Lisinopril 10mg because she lost the bottle - $72.30

Nov 28 - Mike said he got Mom's new pain medication from Walgreens - Meloxicam 15mg, 30 tabs, $55.40

11/30 - Sarah picked up Vitamin D3 supplement (doctor recommended for bone health) at Target - $23.99
EOF

chown ga:ga "$TEXT_PATH"

echo "✅ Receipt text file created at: $TEXT_PATH"

# Open the text file in a text editor for reference
echo "Opening receipt text file for reference..."
su - ga -c "DISPLAY=:1 gedit '$TEXT_PATH' > /dev/null 2>&1 &"
sleep 2

# Launch ONLYOFFICE Spreadsheet Editor with new blank spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
OUTPUT_PATH="$WORKSPACE_DIR/november_med_reconciliation.xlsx"

# Create a minimal blank spreadsheet to open
cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Med Reconciliation"

# Add a hint in cell A1
ws['A1'] = "Date"
ws['B1'] = "Purchaser"
ws['C1'] = "Pharmacy"
ws['D1'] = "Medication"
ws['E1'] = "Cost"
ws['F1'] = "Flag"

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$OUTPUT_PATH"
chown ga:ga "$OUTPUT_PATH"

echo "✅ Blank spreadsheet created at: $OUTPUT_PATH"

# Launch ONLYOFFICE with the spreadsheet
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$OUTPUT_PATH' > /tmp/onlyoffice_med_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_med_task.log || true
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

echo "=== Eldercare Med Reconciliation Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  You and your two siblings (Mike, Sarah, and You) split costs for your mother's medications."
echo "  Last month's receipts are in the text file (check gedit window)."
echo ""
echo "📝 YOUR TASK:"
echo "  Create a reconciliation spreadsheet with:"
echo ""
echo "  1. DATA TABLE (rows 2-9):"
echo "     - Extract all 8 medication purchases from the text file"
echo "     - Columns: Date | Purchaser | Pharmacy | Medication | Cost | Flag"
echo "     - Parse: dates (11/3, Nov 8, etc), purchaser (Mike/Sarah/Me), costs (\$XX.XX)"
echo ""
echo "  2. CALCULATIONS (below the data):"
echo "     - Total Monthly Cost (sum all costs → should be \$335.00)"
echo "     - Cost Per Person (total ÷ 3 → should be ~\$111.67)"
echo "     - Individual sums: Mike Paid, Sarah Paid, You Paid"
echo "     - Balance for each person (amount paid - cost per person)"
echo "       * Positive balance = they're owed money"
echo "       * Negative balance = they owe money"
echo ""
echo "  3. HIGH-COST FLAGGING:"
echo "     - Mark any purchase over \$75 as 'High Cost - Discuss'"
echo "     - Should flag: Amlodipine (\$89.50) and Lisinopril (\$72.30... wait, that's under)"
echo "     - Actually: Amlodipine (\$89.50) should be flagged"
echo ""
echo "  4. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 TIP: Reference the gedit window with the receipts while building the spreadsheet"
echo ""
echo "Expected medications to extract:"
echo "  1. 11/3 - Mike - Walgreens - Metformin 1000mg - \$47.82"
echo "  2. 11/8 - Sarah - CVS - Amlodipine 5mg - \$89.50 (FLAG)"
echo "  3. 11/12 - You - CVS - Atorvastatin - \$15.00"
echo "  4. 11/15 - Mike - Walgreens - Omeprazole 20mg - \$18.99"
echo "  5. 11/19 - Sarah - Mail Order - Levothyroxine 50mcg - \$12.00"
echo "  6. 11/23 - You - CVS - Lisinopril 10mg - \$72.30"
echo "  7. 11/28 - Mike - Walgreens - Meloxicam 15mg - \$55.40"
echo "  8. 11/30 - Sarah - Target - Vitamin D3 - \$23.99"