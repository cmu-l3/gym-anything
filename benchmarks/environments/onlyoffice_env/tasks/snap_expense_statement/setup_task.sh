#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up SNAP Expense Statement Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
DOCS_DIR="/home/ga/Documents"
SHEET_DIR="$DOCS_DIR/Spreadsheets"
sudo -u ga mkdir -p "$DOCS_DIR"
sudo -u ga mkdir -p "$SHEET_DIR"

# Create the expense notes text file with Maria's disorganized data
NOTES_PATH="$DOCS_DIR/expense_notes.txt"

cat > "$NOTES_PATH" << 'EOF'
SNAP Recertification - Expense Notes
Due: December 15th

Rent: $875 per month (lease with Valley Vista Apartments)
Electric bill last month: $67.23 (APS account)
Gas/heating: around $43 in winter (Southwest Gas)
Water bill quarterly: $87 total / 3 = $29/month

Sister Maria watches kids after school: $200/month (cash)

Medical stuff:
- Jamie's inhaler refill: $35 copay (monthly)
- My diabetes meds: $50/month after insurance
- Doctor visit copays: maybe $0-30/month (average $0 for now, just prescriptions)

Phone bill: $45/month (prepaid Cricket)

Case worker said I need this in a spreadsheet format with categories and totals.
Last time I hand-wrote it and they made me redo it. Really stressed about getting this right.

IMPORTANT: Need to submit by December 15th or benefits get suspended!
EOF

chown ga:ga "$NOTES_PATH"

echo "✅ Expense notes created at: $NOTES_PATH"

# Launch ONLYOFFICE Document Editor with the notes file (for reference)
echo "Launching ONLYOFFICE Document Editor with expense notes..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$NOTES_PATH' > /tmp/onlyoffice_snap_notes.log 2>&1 &"

# Wait for first instance to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "WARNING: ONLYOFFICE Document Editor may not have started"
    cat /tmp/onlyoffice_snap_notes.log || true
fi

# Wait for window to appear
if ! wait_for_window "ONLYOFFICE" 25; then
    echo "WARNING: ONLYOFFICE window did not appear yet"
fi

sleep 3

# Now launch ONLYOFFICE Spreadsheet Editor (new blank spreadsheet)
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors --new:cell > /tmp/onlyoffice_snap_sheet.log 2>&1 &"

# Wait for spreadsheet to open
sleep 5

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 400 click 1" || true
sleep 1

# Focus the most recent ONLYOFFICE window (spreadsheet)
focus_onlyoffice_window

echo "=== SNAP Expense Statement Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  Maria needs to create a SNAP recertification expense statement."
echo "  Her disorganized notes are open in the Document Editor."
echo "  A blank spreadsheet is ready for data entry."
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "  1. Review the expense notes in the text document"
echo "  2. Create a properly formatted spreadsheet with:"
echo "     - Title: 'SNAP Recertification Expense Statement'"
echo "     - Household Size: 3"
echo "     - Column headers: 'Expense Category' and 'Monthly Amount'"
echo "  3. Enter expense categories and amounts:"
echo "     - Housing (Rent/Mortgage): \$875"
echo "     - Electric: \$67"
echo "     - Gas/Heating: \$43"
echo "     - Water/Sewer: \$29"
echo "     - Childcare: \$200"
echo "     - Medical (Out-of-Pocket): \$85 (35+50)"
echo "     - Phone: \$45 (optional)"
echo "  4. Create a SUM formula for total expenses (NOT a manually typed number)"
echo "  5. Apply currency formatting to all amounts"
echo "  6. Save as 'SNAP_Expense_Statement.xlsx' in Spreadsheets folder"
echo ""
echo "⚠️  CRITICAL: Use a real =SUM() formula, not a hard-coded total!"
echo ""