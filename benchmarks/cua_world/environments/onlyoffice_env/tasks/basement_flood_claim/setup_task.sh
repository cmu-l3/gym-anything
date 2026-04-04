#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Basement Flood Claim Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet
SHEET_PATH="$WORKSPACE_DIR/basement_flood_claim.xlsx"

cat > /tmp/create_claim_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Flood Damage Inventory"

# Add minimal instructions/template structure
ws['A1'] = "BASEMENT FLOOD DAMAGE INVENTORY"
ws['A1'].font = Font(size=14, bold=True)

ws['A2'] = "Claimant Name:"
ws['A3'] = "Date of Incident:"
ws['A4'] = "Claim Number:"

# Leave space for user to fill in details

ws['A6'] = "Create your inventory below with:"
ws['A7'] = "- Categories (Furniture, Electronics, Decorations, Tools)"
ws['A8'] = "- Item descriptions and quantities"
ws['A9'] = "- Estimated values and photo references"
ws['A10'] = "- Formulas for subtotals and grand total"
ws['A11'] = ""
ws['A12'] = "Required items to document:"
ws['A13'] = "✓ Sectional sofa, Mini fridge, 55\" Smart TV, PlayStation 5"
ws['A14'] = "✓ Christmas tree, Ornament boxes (4), Drill set, Metal shelving (2)"
ws['A15'] = "✓ Add 4+ more damaged items"

# Set column widths for readability
ws.column_dimensions['A'].width = 40

wb.save(sys.argv[1])
print(f"Claim spreadsheet template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_claim_sheet.py
python3 /tmp/create_claim_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_flood_claim.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_flood_claim.log || true
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

echo "=== Basement Flood Claim Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "You returned from vacation to find your basement flooded from a burst pipe."
echo "Your insurance adjuster needs a detailed inventory within 48 hours."
echo ""
echo "📝 REQUIREMENTS:"
echo "  1. Header section with:"
echo "     - Document title: 'Basement Flood Damage Inventory'"
echo "     - Your name: Alex Rivera"
echo "     - Date of incident: January 15, 2025"
echo "     - Claim number: CLM-2025-8847"
echo ""
echo "  2. Create columns for:"
echo "     - Category (Furniture, Electronics, Decorations, Tools)"
echo "     - Item Description"
echo "     - Quantity"
echo "     - Estimated Value (each)"
echo "     - Photo References"
echo "     - Subtotal (Quantity × Value - use FORMULA)"
echo ""
echo "  3. Include these specific damaged items:"
echo "     - Sectional sofa (Furniture) - 1 @ \$1200"
echo "     - Mini refrigerator (Furniture) - 1 @ \$180"
echo "     - 55\" Smart TV (Electronics) - 1 @ \$450"
echo "     - PlayStation 5 (Electronics) - 1 @ \$500"
echo "     - Artificial Christmas tree (Decorations) - 1 @ \$250"
echo "     - Ornament storage boxes (Decorations) - 4 @ \$30 each"
echo "     - Cordless drill set (Tools) - 1 @ \$120"
echo "     - Metal storage shelving (Tools) - 2 @ \$85 each"
echo ""
echo "  4. Add at least 4 MORE items (be creative!)"
echo ""
echo "  5. Use FORMULAS for:"
echo "     - Subtotals: =Quantity * EstimatedValue"
echo "     - Category subtotals: =SUM(range)"
echo "     - Grand total: =SUM(all category subtotals)"
echo ""
echo "  6. Format currency values with \$ symbol"
echo ""
echo "  7. Save the spreadsheet (Ctrl+S)"
echo ""
echo "⚠️  The adjuster specifically wants FORMULAS (not typed numbers) to ensure accuracy!"