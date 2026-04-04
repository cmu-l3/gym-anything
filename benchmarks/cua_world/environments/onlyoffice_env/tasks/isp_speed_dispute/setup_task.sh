#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up ISP Speed Dispute Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with messy speed test data
SHEET_PATH="$WORKSPACE_DIR/speed_test_data.xlsx"

cat > /tmp/create_speed_data.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font
import sys

wb = Workbook()

# Sheet 1: Raw messy data
ws = wb.active
ws.title = "RawData"

# Messy headers (inconsistent capitalization)
ws['A1'] = "date"
ws['B1'] = "time"
ws['C1'] = "service"
ws['D1'] = "download"
ws['E1'] = "upload"

# Add messy speed test data over 2 weeks
# Intentionally inconsistent time formats, missing upload data, etc.
data = [
    ["1/15/25", "9:30 PM", "Speedtest", 287, 35],
    ["1/15/25", "2200", "Fast", 245, None],  # Missing upload, 24-hour format
    ["1/16/25", "10:15am", "ISP test", 298, 38],  # AM/PM format
    ["1/16/25", "19:45", "Speedtest", 156, 22],  # Evening, poor speed
    ["1/17/25", "8:00 AM", "Fast", 201, None],
    ["1/17/25", "1830", "Speedtest", 178, 25],  # Evening
    ["1/18/25", "11:00pm", "Fast", 198, None],  # Late evening
    ["1/19/25", "07:30", "Speedtest", 289, 37],  # Morning, good speed
    ["1/19/25", "6:15 PM", "ISP test", 165, 21],  # Evening, poor
    ["1/20/25", "2330", "Fast", 187, None],  # Late night
    ["1/22/25", "8:45am", "Speedtest", 276, 34],  # Morning
    ["1/23/25", "19:00", "Fast", 144, None],  # Evening, very poor
    ["1/24/25", "09:00", "Speedtest", 291, 38],  # Morning, good
    ["1/25/25", "8:30 PM", "ISP test", 152, 19],  # Evening, poor
]

for i, row_data in enumerate(data, start=2):
    for j, value in enumerate(row_data, start=1):
        ws.cell(row=i, column=j, value=value)

# Sheet 2: Notes with context
ws2 = wb.create_sheet("Notes")
ws2['A1'] = "Advertised speed: 300 Mbps download / 40 Mbps upload"
ws2['A2'] = "Contract started: December 2024"
ws2['A3'] = "Monthly cost: $79.99"
ws2['A4'] = ""
ws2['A5'] = "Problem: Speeds consistently below advertised, especially evenings"
ws2['A6'] = "Goal: Build evidence for service credit or contract cancellation"

# Make notes bold
ws2['A1'].font = Font(bold=True)
ws2['A5'].font = Font(bold=True)

wb.save(sys.argv[1])
print(f"Speed test data spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_speed_data.py
python3 /tmp/create_speed_data.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_isp_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_isp_task.log || true
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

echo "=== ISP Speed Dispute Task Setup Complete ==="
echo "📝 Task Instructions:"
echo ""
echo "You need to organize internet speed test data to dispute slow service with ISP."
echo ""
echo "Required actions:"
echo "  1. Review the messy data in RawData sheet (inconsistent times, missing values)"
echo "  2. Add a column calculating % of advertised speed (300 Mbps)"
echo "     Formula example: =(D2/300)*100"
echo "  3. Add a column categorizing time as 'Peak' (5 PM-11 PM) or 'Off-Peak'"
echo "  4. Calculate AVERAGE download speed across all tests"
echo "  5. Calculate AVERAGE for Peak vs Off-Peak periods"
echo "  6. Create a SUMMARY section with:"
echo "     - Advertised Speed: 300 Mbps"
echo "     - Average Actual Speed: [your calculation]"
echo "     - Percentage Received: [your calculation]"
echo "     - Worst Time Period: [Peak or Off-Peak]"
echo "  7. (Optional) Add conditional formatting to highlight speeds < 210 Mbps"
echo "  8. Save the file (Ctrl+S)"
echo ""
echo "Expected insights:"
echo "  - Average speed should be around 215-220 Mbps (~72% of advertised)"
echo "  - Evening/Peak hours perform worse than morning/off-peak"
echo "  - Multiple tests below 70% threshold (210 Mbps)"