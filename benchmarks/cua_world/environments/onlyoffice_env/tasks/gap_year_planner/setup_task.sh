#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Gap Year Planner Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with raw data
RAW_DATA_PATH="$WORKSPACE_DIR/gap_year_raw_data.xlsx"

cat > /tmp/create_gap_year_raw.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()

# Sheet 1: RawNotes - messy unstructured information
ws_raw = wb.active
ws_raw.title = "RawNotes"

# Add messy notes as text
raw_notes = """Messy unstructured notes:

Thailand - planning 45 days, visa needed apply by May 15th 2025
Budget around $35/day maybe $40 to be safe
Vaccines: Typhoid, Hep A, routine stuff

Vietnam - 30 days, visa on arrival is easier
Cheaper than Thailand maybe $28/day
Same vaccines as Thailand basically
Visa deadline June 1st 2025

Portugal - 60 days, NO VISA (EU Schengen rules)
More expensive, budget $70/day
Just routine vaccines, maybe rabies if rural areas
Should book by June 1st 2025 anyway

Iceland - 21 days, no visa needed (Schengen)
EXPENSIVE. $120/day minimum. Bring instant ramen.
No special vaccines just don't die of cold
No deadline but going in July

IMPORTANT: Thai visa due May 15, Vietnam by June 1st
Portugal and Iceland don't need visas but should plan ahead"""

# Split into lines and add to cells
lines = raw_notes.split('\n')
for i, line in enumerate(lines, start=1):
    ws_raw.cell(row=i, column=1, value=line)
    ws_raw.cell(row=i, column=1).alignment = Alignment(wrap_text=True)

# Make column A wider
ws_raw.column_dimensions['A'].width = 80

# Sheet 2: Template - partially structured template
ws_template = wb.create_sheet(title="Template")

# Add column headers
headers = [
    "Country",
    "Duration (days)",
    "Daily Budget (USD)",
    "Total Cost",
    "Visa Required?",
    "Visa Deadline",
    "Vaccines Needed"
]

for col_idx, header in enumerate(headers, start=1):
    cell = ws_template.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='center')

# Set column widths
ws_template.column_dimensions['A'].width = 15
ws_template.column_dimensions['B'].width = 15
ws_template.column_dimensions['C'].width = 18
ws_template.column_dimensions['D'].width = 15
ws_template.column_dimensions['E'].width = 15
ws_template.column_dimensions['F'].width = 15
ws_template.column_dimensions['G'].width = 30

# Add one empty row to show structure
for col_idx in range(1, 8):
    ws_template.cell(row=2, column=col_idx, value="")

wb.save(sys.argv[1])
print(f"Gap year raw data spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_gap_year_raw.py
python3 /tmp/create_gap_year_raw.py "$RAW_DATA_PATH"
chown ga:ga "$RAW_DATA_PATH"

echo "✅ Raw data spreadsheet created at: $RAW_DATA_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$RAW_DATA_PATH' > /tmp/onlyoffice_gap_year_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_gap_year_task.log || true
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

echo "=== Gap Year Planner Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review the RawNotes sheet with messy travel information"
echo "  2. Use the Template sheet as a starting point"
echo "  3. Create a structured table with 7 columns:"
echo "     - Country, Duration (days), Daily Budget (USD), Total Cost"
echo "     - Visa Required?, Visa Deadline, Vaccines Needed"
echo "  4. Extract data for all 4 countries from RawNotes"
echo "  5. Add formulas: Total Cost = Duration × Daily Budget"
echo "  6. Add a TOTAL summary row with SUM/AVERAGE formulas"
echo "  7. Sort countries by Visa Deadline (earliest first)"
echo "  8. Apply formatting: bold headers, currency format"
echo "  9. Save as: /home/ga/Documents/Spreadsheets/gap_year_plan.xlsx"
echo ""
echo "Countries to include:"
echo "  - Thailand (45 days, ~$35-40/day, visa by May 15, 2025)"
echo "  - Vietnam (30 days, ~$28/day, visa by June 1, 2025)"
echo "  - Portugal (60 days, ~$70/day, no visa)"
echo "  - Iceland (21 days, ~$120/day, no visa)"