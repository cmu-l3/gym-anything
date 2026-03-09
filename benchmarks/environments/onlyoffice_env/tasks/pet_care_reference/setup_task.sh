#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Pet Care Reference Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet template with column headers
SHEET_PATH="$WORKSPACE_DIR/pet_care_reference.xlsx"

cat > /tmp/create_pet_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font
import sys

wb = Workbook()
ws = wb.active
ws.title = "Pet Care"

# Add column headers
headers = [
    "Pet Name",
    "Breed/Type",
    "Age",
    "Medication Name",
    "Dosage & Frequency",
    "Daily Feeding Amount",
    "Next Vet Appointment",
    "Days Until Appointment"
]

for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx)
    cell.value = header
    cell.font = Font(bold=True)

# Add instruction row
ws['A2'] = "Bella"
ws['A3'] = "Max"

# Set column widths for readability
ws.column_dimensions['A'].width = 15
ws.column_dimensions['B'].width = 20
ws.column_dimensions['C'].width = 8
ws.column_dimensions['D'].width = 20
ws.column_dimensions['E'].width = 20
ws.column_dimensions['F'].width = 20
ws.column_dimensions['G'].width = 20
ws.column_dimensions['H'].width = 22

wb.save(sys.argv[1])
print(f"Pet care spreadsheet template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_pet_sheet.py
python3 /tmp/create_pet_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Pet care spreadsheet template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_pet_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_pet_task.log || true
    # Don't exit - let the task continue
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
    # Don't exit - let the task continue
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Pet Care Reference Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Fill in pet information for two dogs:"
echo ""
echo "  Bella (Row 2):"
echo "    - Breed: Golden Retriever"
echo "    - Age: 8"
echo "    - Medication: Carprofen (arthritis)"
echo "    - Dosage: 75mg twice daily"
echo "    - Feeding: 2 cups, twice daily"
echo "    - Next Appointment: 2024-03-15"
echo "    - Days Until: =G2-TODAY() (formula)"
echo ""
echo "  Max (Row 3):"
echo "    - Breed: Mixed breed rescue"
echo "    - Age: 3"
echo "    - Medication: Apoquel (allergies)"
echo "    - Dosage: 16mg once daily"
echo "    - Feeding: 1.5 cups, twice daily"
echo "    - Next Appointment: 2024-03-08"
echo "    - Days Until: =G3-TODAY() (formula)"
echo ""
echo "  Then save the spreadsheet (Ctrl+S)"