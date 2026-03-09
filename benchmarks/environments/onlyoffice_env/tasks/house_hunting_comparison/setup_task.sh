#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up House Hunting Comparison Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet for the user to fill
SHEET_PATH="$WORKSPACE_DIR/house_comparison.xlsx"

cat > /tmp/create_house_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Properties"

# Create completely blank spreadsheet - user will add everything
# This makes it a realistic scenario where they're starting from scratch

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_house_sheet.py
python3 /tmp/create_house_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_house_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_house_task.log || true
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

echo "=== House Hunting Comparison Task Setup Complete ==="
echo ""
echo "📝 SCENARIO: You're house hunting and need to compare properties to make a decision."
echo ""
echo "✏️  INSTRUCTIONS:"
echo ""
echo "1. CREATE HEADERS (Row 1):"
echo "   A1: Address"
echo "   B1: Price"
echo "   C1: Square Feet"
echo "   D1: Bedrooms"
echo "   E1: Bathrooms"
echo "   F1: Price per Sq Ft"
echo ""
echo "2. ENTER PROPERTY DATA (Rows 2-5):"
echo "   Row 2: 742 Evergreen Terrace | 385000 | 2100 | 3 | 2"
echo "   Row 3: 1640 Riverside Drive | 425000 | 2450 | 4 | 2.5"
echo "   Row 4: 344 Clinton Way | 310000 | 1650 | 2 | 2"
echo "   Row 5: 2311 North Los Robles | 468000 | 2800 | 4 | 3"
echo ""
echo "3. ADD FORMULAS (Column F, Rows 2-5):"
echo "   F2: =B2/C2  (price ÷ square feet)"
echo "   F3: =B3/C3"
echo "   F4: =B4/C4"
echo "   F5: =B5/C5"
echo ""
echo "4. FORMAT AS CURRENCY:"
echo "   - Select column B (Price)"
echo "   - Apply currency format ($ with 2 decimals)"
echo "   - Select column F (Price per Sq Ft)"
echo "   - Apply currency format ($ with 2 decimals)"
echo ""
echo "5. ADD SUMMARY (Row 7):"
echo "   A7: Best Value (Lowest $/SqFt):"
echo "   B7: =MIN(F2:F5)"
echo ""
echo "6. SAVE: Press Ctrl+S"
echo ""
echo "💡 TIP: This will help you identify which house offers the best value per square foot!"