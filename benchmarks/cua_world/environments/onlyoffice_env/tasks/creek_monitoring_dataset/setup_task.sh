#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Creek Monitoring Dataset Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create blank spreadsheet
SHEET_PATH="$WORKSPACE_DIR/mill_creek_data.xlsx"

cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Mill Creek Data"

# Start with a completely blank sheet
# The agent needs to add everything

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Create reference file with raw sample data
NOTES_PATH="$WORKSPACE_DIR/sampling_notes.txt"

cat > "$NOTES_PATH" << 'DATAEOF'
MILL CREEK WATER QUALITY SAMPLING DATA
=======================================

Sample 1: April 3, 2025, 7:45 AM, Site A (downstream), pH 6.8, DO 7.2, Nitrates 2.1, Temp 14°C, Sunny, "Baseline sample"

Sample 2: April 10, 2025, 7:30 AM, Site A, pH 6.7, DO 7.4, Nitrates 2.3, Temp 15°C, Sunny, "Normal conditions"

Sample 3: April 17, 2025, 8:00 AM, Site A, pH 6.2, DO 5.8, Nitrates 8.4, Temp 16°C, Cloudy, "First dead fish observed"

Sample 4: April 17, 2025, 8:20 AM, Site B (upstream), pH 7.1, DO 7.8, Nitrates 1.9, Temp 16°C, Cloudy, "Upstream comparison"

Sample 5: April 24, 2025, 7:45 AM, Site A, pH 5.9, DO 5.1, Nitrates 12.7, Temp 17°C, Sunny, "Algae bloom visible"

Sample 6: May 1, 2025, 7:50 AM, Site A, pH 6.0, DO 4.8, Nitrates 15.2, Temp MISSING, Partly cloudy, "Strong chemical smell"

Sample 7: May 8, 2025, 7:40 AM, Site A, pH 11.2, DO 6.2, Nitrates 14.8, Temp 19°C, Sunny, "KIT MALFUNCTION - DISREGARD pH"

Sample 8: May 8, 2025, 8:00 AM, Site B, pH 7.0, DO 7.9, Nitrates 2.0, Temp 19°C, Sunny, "Upstream still normal"

Sample 9: May 15, 2025, 2:30 PM, Site A, pH 6.1, DO 3.9, Nitrates 18.5, Temp 21°C, Heavy rain, "After 2-inch rainfall"

Sample 10: May 22, 2025, 7:35 AM, Site A, pH 6.3, DO 4.2, Nitrates 16.1, Temp MISSING, Sunny, "Conditions worsening"

Sample 11: May 29, 2025, 7:45 AM, Site A, pH 6.4, DO 4.5, Nitrates 14.9, Temp 22°C, Sunny, "Steady pollution"

Sample 12: May 29, 2025, 8:10 AM, Site C (industrial area), pH 8.9, DO 9.2, Nitrates 45.3, Temp 25°C, Sunny, "FOUND SOURCE - near factory outflow"

=======================================
INSTRUCTIONS FOR SPREADSHEET:

1. Create headers in row 1:
   - Date, Time, Location Code, pH, Dissolved Oxygen (mg/L), Nitrates (ppm), Water Temp (°C), Weather, Notes

2. Enter all 12 samples in rows 2-13

3. Add summary calculations (around row 16-20):
   - Average pH (MUST exclude Sample 7 due to kit malfunction)
   - Average Dissolved Oxygen
   - Average Nitrates
   - Maximum Nitrates
   - Count of samples where DO < 5.0 (critical threshold for fish)

4. Apply conditional formatting:
   - pH outside 6.5-8.5 range: highlight in RED
   - Dissolved Oxygen below 5.0: highlight in ORANGE
   - Nitrates above 10 ppm: highlight in YELLOW

5. Add data validation to pH column (rows 2-13):
   - Must be between 0 and 14
   - Show error message: "pH must be between 0 and 14"

CONTEXT: This data will be presented to city council next week to demonstrate pollution in Mill Creek.
DATAEOF

chown ga:ga "$NOTES_PATH"

echo "✅ Reference data file created at: $NOTES_PATH"

# Launch ONLYOFFICE with the blank spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_creek_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 25; then
    echo "WARNING: ONLYOFFICE process not detected, but continuing..."
    cat /tmp/onlyoffice_creek_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "WARNING: ONLYOFFICE window not detected, but continuing..."
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

# Also open the reference file in a text editor for easy access
echo "Opening reference file in text editor..."
su - ga -c "DISPLAY=:1 mousepad '$NOTES_PATH' > /tmp/mousepad_notes.log 2>&1 &" || true
sleep 2

echo "=== Creek Monitoring Dataset Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  Sarah has been monitoring Mill Creek water quality after noticing dead fish."
echo "  She needs to organize 12 samples into a professional dataset for city council."
echo ""
echo "📝 FILES:"
echo "  - Blank spreadsheet: $SHEET_PATH"
echo "  - Reference data: $NOTES_PATH"
echo ""
echo "✅ REQUIREMENTS:"
echo "  1. Create proper column headers in row 1"
echo "  2. Enter all 12 samples (rows 2-13)"
echo "  3. Add summary calculations with formulas"
echo "  4. Apply conditional formatting to highlight problems"
echo "  5. Add data validation to pH column"
echo "  6. Save the spreadsheet (Ctrl+S)"
echo ""
echo "⚠️  NOTE: Sample 7 has kit malfunction - pH should still be entered but EXCLUDED from average calculation"
echo ""