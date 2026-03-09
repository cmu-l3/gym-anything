#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Lab Notebook Digitization Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
WORKSPACE_DIR="/home/ga/Documents/lab_notebook_digitization"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the raw notebook data text file
RAW_DATA_FILE="$WORKSPACE_DIR/raw_notebook_excerpt.txt"

cat > "$RAW_DATA_FILE" << 'DATAEOF'
===============================================
Lab Notebook - Plant Growth Experiment
Student: Maya Chen
Experiment: Drought stress response in Arabidopsis
===============================================

Day 1 - 3/15/2024
Treatment: WW (well-watered)
Plant #1: 3.2cm, Plant #2: 3.4cm, Plant #3: 3.1cm
Avg = 3.23 (calculated on paper)

Treatment: DS (drought stress)
Plant #1: 3.0cm, Plant #2: N/M (wilted), Plant #3: 2.9cm
Avg = 2.95

Day 2 - March 16 2024
Treatment: Control
Plant #1: 35mm, Plant #2: 37mm, Plant #3: 33mm
Avg = 3.5cm (quick calc)

Treatment: Drought
Plant #1: 31mm, Plant #2: ?, Plant #3: 29mm
Avg = 3.0cm

Day 3 - 3/17
Treatment: WW
Plant #1: 38mm, Plant #2: 39mm, Plant #3: 36mm
Avg calculated: 3.77

Treatment: DS
Plant #1: 33mm, Plant #2: still wilted, Plant #3: 31mm
Avg = 3.2

===============================================
Notes:
- Switched from cm to mm measurements on Day 2 (forgot to note initially)
- Plant #2 in drought treatment has been consistently problematic
- Need to digitize this for lab meeting tomorrow!
===============================================
DATAEOF

chown ga:ga "$RAW_DATA_FILE"

# Also copy to Desktop for easy access
sudo -u ga cp "$RAW_DATA_FILE" /home/ga/Desktop/
echo "✅ Raw notebook data created at: $RAW_DATA_FILE"
echo "✅ Copy also placed on Desktop for easy access"

# Create a blank starter spreadsheet with instructions
STARTER_FILE="$WORKSPACE_DIR/growth_data_cleaned.xlsx"

cat > /tmp/create_starter.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "GrowthData"

# Add instruction in first cell
ws['A1'] = "INSTRUCTIONS: Convert the raw notebook data from ~/Desktop/raw_notebook_excerpt.txt into a clean data table below."
ws['A1'].font = Font(bold=True, size=12, color="0000FF")
ws['A1'].alignment = Alignment(wrap_text=True)
ws.merge_cells('A1:G1')
ws.row_dimensions[1].height = 30

# Add suggested column headers (the user should replace/modify these)
ws['A3'] = "Date"
ws['B3'] = "Treatment"
ws['C3'] = "Plant_1_cm"
ws['D3'] = "Plant_2_cm"
ws['E3'] = "Plant_3_cm"
ws['F3'] = "Mean_Height_cm"
ws['G3'] = "Notes"

# Make headers bold
for cell in ws[3]:
    cell.font = Font(bold=True)

# Adjust column widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 12
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 12
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 15
ws.column_dimensions['G'].width = 20

wb.save(sys.argv[1])
print(f"Starter spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_starter.py
python3 /tmp/create_starter.py "$STARTER_FILE"
chown ga:ga "$STARTER_FILE"

echo "✅ Starter spreadsheet created at: $STARTER_FILE"

# Open the text file in a text editor first (gedit) so user can reference it
echo "Opening raw data file in text editor..."
su - ga -c "DISPLAY=:1 gedit /home/ga/Desktop/raw_notebook_excerpt.txt > /tmp/gedit.log 2>&1 &"
sleep 2

# Wait for gedit window
if wait_for_window "gedit" 10; then
    echo "✅ Text editor opened with raw data"
    # Position gedit on the left side of screen
    su - ga -c "DISPLAY=:1 wmctrl -r 'gedit' -e 0,0,0,800,1000" || true
else
    echo "⚠️ Text editor did not open, but continuing..."
fi

sleep 1

# Launch ONLYOFFICE with the starter spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$STARTER_FILE' > /tmp/onlyoffice_lab_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_lab_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Position ONLYOFFICE on the right side of screen
sleep 2
su - ga -c "DISPLAY=:1 wmctrl -r 'ONLYOFFICE' -e 0,800,0,1120,1000" || true

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 1200 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Lab Notebook Digitization Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  Raw notebook data is available in:"
echo "    - Text editor (left side of screen)"
echo "    - File: /home/ga/Desktop/raw_notebook_excerpt.txt"
echo ""
echo "  Your task:"
echo "  1. Read the raw notebook data (dates, treatments, measurements)"
echo "  2. Create a clean data table in the spreadsheet"
echo "  3. Standardize ALL dates to YYYY-MM-DD format (e.g., 2024-03-15)"
echo "  4. Standardize treatment codes: 'WW' for well-watered, 'DS' for drought"
echo "  5. Convert ALL measurements to centimeters (Day 2-3 are in mm!)"
echo "  6. Use AVERAGE() formulas to calculate means (don't hardcode)"
echo "  7. Flag missing data appropriately (N/A, blank, or notes)"
echo "  8. Save as: /home/ga/Documents/lab_notebook_digitization/growth_data_cleaned.xlsx"
echo ""
echo "Expected data rows: 6 (2 treatments × 3 days)"
echo "Key conversions: 35mm = 3.5cm, 38mm = 3.8cm, etc."
echo "Missing values: Plant #2 in DS treatment on Days 1, 2, 3"