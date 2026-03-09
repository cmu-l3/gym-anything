#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Mystery Shop Report Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the mystery shop evaluation spreadsheet
SHEET_PATH="$WORKSPACE_DIR/mystery_shop_riverside_diner.xlsx"

cat > /tmp/create_mystery_shop.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "Evaluation Report"

# Header
ws['A1'] = "Riverside Diner Mystery Shop Evaluation"
ws['A1'].font = Font(size=14, bold=True)
ws.merge_cells('A1:D1')
ws['A1'].alignment = Alignment(horizontal='center')

# Shop details
ws['A3'] = "Shop Date:"
ws['B3'] = "2024-01-15"
ws['C3'] = "Shopper ID:"
ws['D3'] = "MS-4782"

ws['A4'] = "Location:"
ws['B4'] = "Riverside Diner, 423 Main St"
ws['C4'] = "Report Due:"
ws['D4'] = "2024-01-16 18:00"

# Section 1: Greeting & Seating
ws['A6'] = "GREETING & SEATING (Weight: 15%)"
ws['A6'].font = Font(bold=True, size=11)
ws['A6'].fill = PatternFill(start_color="E7E6E6", end_color="E7E6E6", fill_type="solid")
ws['A7'] = "Criteria"
ws['B7'] = "Score (1-5)"
ws['C7'] = "Notes"
ws['A7'].font = Font(bold=True)
ws['B7'].font = Font(bold=True)
ws['C7'].font = Font(bold=True)

ws['A8'] = "Greeted within 2 minutes"
ws['A9'] = "Staff made eye contact"
ws['A10'] = "Seated promptly"
ws['A11'] = "Section Average:"
ws['A11'].font = Font(italic=True, bold=True)

# Section 2: Service Quality
ws['A13'] = "SERVICE QUALITY (Weight: 35%)"
ws['A13'].font = Font(bold=True, size=11)
ws['A13'].fill = PatternFill(start_color="E7E6E6", end_color="E7E6E6", fill_type="solid")
ws['A14'] = "Criteria"
ws['B14'] = "Score (1-5)"
ws['C14'] = "Notes"
ws['A14'].font = Font(bold=True)
ws['B14'].font = Font(bold=True)
ws['C14'].font = Font(bold=True)

ws['A15'] = "Server introduced themselves"
ws['A16'] = "Drink refills without asking"
ws['A17'] = "Checked back within 2 bites"
ws['A18'] = "Knowledgeable about menu"
ws['A19'] = "Handled special request well"
ws['A20'] = "Section Average:"
ws['A20'].font = Font(italic=True, bold=True)

# Section 3: Food Quality
ws['A22'] = "FOOD QUALITY (Weight: 25%)"
ws['A22'].font = Font(bold=True, size=11)
ws['A22'].fill = PatternFill(start_color="E7E6E6", end_color="E7E6E6", fill_type="solid")
ws['A23'] = "Criteria"
ws['B23'] = "Score (1-5)"
ws['C23'] = "Notes"
ws['A23'].font = Font(bold=True)
ws['B23'].font = Font(bold=True)
ws['C23'].font = Font(bold=True)

ws['A24'] = "Food temperature appropriate"
ws['A25'] = "Presentation appealing"
ws['A26'] = "Portion size adequate"
ws['A27'] = "Taste met expectations"
ws['A28'] = "Section Average:"
ws['A28'].font = Font(italic=True, bold=True)

# Section 4: Cleanliness
ws['A30'] = "CLEANLINESS (Weight: 15%)"
ws['A30'].font = Font(bold=True, size=11)
ws['A30'].fill = PatternFill(start_color="E7E6E6", end_color="E7E6E6", fill_type="solid")
ws['A31'] = "Criteria"
ws['B31'] = "Score (1-5)"
ws['C31'] = "Notes"
ws['A31'].font = Font(bold=True)
ws['B31'].font = Font(bold=True)
ws['C31'].font = Font(bold=True)

ws['A32'] = "Table clean upon seating"
ws['A33'] = "Restroom well-maintained"
ws['A34'] = "Overall tidiness"
ws['A35'] = "Section Average:"
ws['A35'].font = Font(italic=True, bold=True)

# Section 5: Payment & Departure
ws['A37'] = "PAYMENT & DEPARTURE (Weight: 10%)"
ws['A37'].font = Font(bold=True, size=11)
ws['A37'].fill = PatternFill(start_color="E7E6E6", end_color="E7E6E6", fill_type="solid")
ws['A38'] = "Criteria"
ws['B38'] = "Score (1-5)"
ws['C38'] = "Notes"
ws['A38'].font = Font(bold=True)
ws['B38'].font = Font(bold=True)
ws['C38'].font = Font(bold=True)

ws['A39'] = "Check delivered promptly"
ws['A40'] = "Receipt accurate"
ws['A41'] = "Section Average:"
ws['A41'].font = Font(italic=True, bold=True)

# Final calculations section
ws['A43'] = "FINAL CALCULATIONS"
ws['A43'].font = Font(bold=True, size=12)
ws['A43'].fill = PatternFill(start_color="D9D9D9", end_color="D9D9D9", fill_type="solid")
ws['A44'] = "Overall Score (out of 5):"
ws['A44'].font = Font(bold=True)
ws['A45'] = "Percentage Score:"
ws['A45'].font = Font(bold=True)
ws['A46'] = "Bonus Eligible (≥85%):"
ws['A46'].font = Font(bold=True)

# Add helpful instructions/notes at bottom
ws['A48'] = "═══════════════════════════════════════════════════════"
ws['A48'].font = Font(bold=True)
ws['A49'] = "HANDWRITTEN NOTES - Your scores to enter above:"
ws['A49'].font = Font(bold=True, size=11, color="0000FF")
ws['A50'] = "Greeting & Seating (rows 8-10): 4, 5, 4"
ws['A51'] = "Service Quality (rows 15-19): 5, 3, 5, 4, 5"
ws['A52'] = "Food Quality (rows 24-27): 4, 5, 5, 4"
ws['A53'] = "Cleanliness (rows 32-34): 3, 4, 4"
ws['A54'] = "Payment & Departure (rows 39-40): 5, 5"
ws['A56'] = "INSTRUCTIONS:"
ws['A56'].font = Font(bold=True, size=11, color="FF0000")
ws['A57'] = "1. Enter scores from notes above into column B"
ws['A58'] = "2. Create AVERAGE formulas in Section Average rows (B11, B20, B28, B35, B41)"
ws['A59'] = "3. Create weighted average in B44: =B11*0.15+B20*0.35+B28*0.25+B35*0.15+B41*0.1"
ws['A60'] = "4. Calculate percentage in B45: =B44/5*100"
ws['A61'] = "5. Create IF formula in B46: =IF(B45>=85,\"YES\",\"NO\")"

# Adjust column widths
ws.column_dimensions['A'].width = 40
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 30
ws.column_dimensions['D'].width = 20

wb.save(sys.argv[1])
print(f"Mystery shop evaluation spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_mystery_shop.py
python3 /tmp/create_mystery_shop.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Mystery shop evaluation spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_mystery_shop_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_mystery_shop_task.log || true
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

echo "=== Mystery Shop Report Task Setup Complete ==="
echo "📝 Task: Complete the mystery shop evaluation report"
echo ""
echo "Your handwritten notes are at the bottom of the spreadsheet."
echo "You need to:"
echo "  1. Enter all scores from notes into column B (17 scores total)"
echo "  2. Create AVERAGE formulas for each section average"
echo "  3. Create weighted overall score formula in B44"
echo "  4. Calculate percentage in B45"
echo "  5. Create IF formula in B46 for bonus eligibility"
echo "  6. Save the file (Ctrl+S)"
echo ""
echo "Expected results:"
echo "  - Section averages: 4.33, 4.40, 4.50, 3.67, 5.00"
echo "  - Overall score: ~4.37"
echo "  - Percentage: ~87.3%"
echo "  - Bonus eligible: YES"