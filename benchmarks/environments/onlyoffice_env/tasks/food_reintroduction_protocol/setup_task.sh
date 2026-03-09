#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Food Reintroduction Protocol Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the source data file with elimination diet tracking notes
SOURCE_DATA_PATH="$WORKSPACE_DIR/reintroduction_notes.txt"

cat > "$SOURCE_DATA_PATH" << 'DATAEOF'
ELIMINATION DIET TRACKING - Zoe (age 8)
Baseline Period (no allergens): March 1-21
Avg symptoms during baseline: Skin=3, Digestive=2, Energy=8

REINTRODUCTION SCHEDULE:
March 22-25: Reintroduced White Rice
  Symptoms: Skin=2, Digestive=1, Energy=9

March 26-29: Reintroduced Chicken  
  Symptoms: Skin=3, Digestive=2, Energy=8

March 30-Apr 2: Reintroduced Eggs
  Symptoms: Skin=7, Digestive=6, Energy=5

April 3-6: Reintroduced Dairy (milk)
  Symptoms: Skin=8, Digestive=8, Energy=4

April 7-10: Reintroduced Gluten (bread)
  Symptoms: Skin=4, Digestive=3, Energy=7

April 11-14: Reintroduced Soy
  Symptoms: Skin=6, Digestive=7, Energy=5

April 15-18: Reintroduced Peanuts
  Symptoms: Skin=3, Digestive=2, Energy=8

April 19-22: Reintroduced Tree Nuts (almonds)
  Symptoms: Skin=4, Digestive=2, Energy=8
DATAEOF

chown ga:ga "$SOURCE_DATA_PATH"
echo "✅ Source data created at: $SOURCE_DATA_PATH"

# Create a starter spreadsheet with instructions
SHEET_PATH="$WORKSPACE_DIR/reintroduction_analysis.xlsx"

cat > /tmp/create_reintro_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "Reintroduction_Analysis"

# Add instructions in the first few rows
ws['A1'] = "FOOD REINTRODUCTION ANALYSIS WORKSHEET"
ws['A1'].font = Font(size=14, bold=True)

ws['A2'] = "Instructions: Review the file 'reintroduction_notes.txt' in this folder."
ws['A3'] = "Create a structured analysis below with the following columns:"
ws['A4'] = "Period | Food_Introduced | Skin_Score | Digestive_Score | Energy_Score | Avg_Symptom_Severity | Trigger_Status"

ws['A5'] = ""
ws['A6'] = "Important:"
ws['A7'] = "- Avg_Symptom_Severity formula: (Skin + Digestive + (10 - Energy)) / 3"
ws['A8'] = "- Trigger_Status formula: IF(Avg > 5, '⚠️ TRIGGER', IF(Avg <= 3, '✓ Safe', '? Monitor'))"
ws['A9'] = "- Include a SUMMARY section after all data rows"

ws['A11'] = "Start your analysis below (suggest starting at row 13 with headers):"

# Make instruction area stand out
for row in range(1, 12):
    ws.row_dimensions[row].height = 18

wb.save(sys.argv[1])
print(f"Starter spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_reintro_sheet.py
python3 /tmp/create_reintro_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Starter spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_reintro_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_reintro_task.log || true
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

echo "=== Food Reintroduction Protocol Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "   A parent's child has been on an elimination diet for eczema and digestive issues."
echo "   The allergist needs a professional spreadsheet showing the reintroduction timeline"
echo "   and symptom patterns to determine if allergy testing is needed (insurance requirement)."
echo ""
echo "📝 TASK:"
echo "   1. Review the data in: reintroduction_notes.txt"
echo "   2. Create a structured analysis spreadsheet with columns:"
echo "      - Period (e.g., 'Baseline', 'March 22-25')"
echo "      - Food_Introduced (e.g., 'None (baseline)', 'White Rice', 'Eggs')"
echo "      - Skin_Score (0-10)"
echo "      - Digestive_Score (0-10)"
echo "      - Energy_Score (0-10, higher is better)"
echo "      - Avg_Symptom_Severity (FORMULA: (Skin + Digestive + (10-Energy))/3)"
echo "      - Trigger_Status (FORMULA: IF logic - see instructions)"
echo "   3. Enter all 9 periods (baseline + 8 reintroduced foods)"
echo "   4. Add a SUMMARY section with:"
echo "      - Count of trigger foods (formula)"
echo "      - Count of safe foods (formula)"
echo "      - Highest severity food (formula)"
echo "   5. Save the spreadsheet (Ctrl+S)"
echo ""
echo "⚕️  MEDICAL CONTEXT:"
echo "   - Skin/Digestive scores: higher = worse symptoms"
echo "   - Energy score: lower = worse (inverted)"
echo "   - Trigger threshold: Avg Severity > 5"
echo "   - Safe threshold: Avg Severity ≤ 3"
echo ""