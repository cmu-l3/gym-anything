#!/bin/bash
echo "=== Setting up SPC Control Charts task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

FILE_PATH="/home/ga/Documents/piston_ring_measurements.xlsx"
rm -f "$FILE_PATH" 2>/dev/null || true

# Generate realistic NIST manufacturing data
python3 << 'PYEOF'
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font

wb = Workbook()
ws = wb.active
ws.title = 'Raw Data'

headers = ['Subgroup', 'X1', 'X2', 'X3', 'X4', 'X5']
ws.append(headers)

# Bold headers
for cell in ws[1]:
    cell.font = Font(bold=True)

# NIST Piston Ring Data
data = [
    [1, 74.030, 74.002, 74.019, 73.992, 74.008],
    [2, 73.995, 73.992, 74.001, 74.011, 74.004],
    [3, 73.988, 74.024, 74.021, 74.005, 74.002],
    [4, 74.002, 73.996, 73.993, 74.015, 74.009],
    [5, 73.992, 74.007, 74.015, 73.989, 74.014],
    [6, 74.009, 73.994, 73.997, 73.985, 73.993],
    [7, 73.995, 74.006, 73.994, 74.000, 74.005],
    [8, 73.985, 74.003, 73.993, 74.015, 73.988],
    [9, 74.008, 73.995, 74.009, 74.005, 74.004],
    [10, 73.998, 74.000, 73.990, 74.007, 73.995],
    [11, 73.994, 73.998, 73.994, 73.995, 73.990],
    [12, 74.004, 74.000, 74.007, 74.000, 73.996],
    [13, 73.983, 74.002, 73.998, 73.997, 74.012],
    [14, 74.006, 73.967, 73.994, 74.000, 73.984],
    [15, 74.012, 74.014, 73.998, 73.999, 74.007],
    [16, 74.000, 73.984, 74.005, 73.998, 73.996],
    [17, 73.994, 74.012, 73.986, 74.005, 74.007],
    [18, 74.006, 74.010, 74.018, 74.003, 74.000],
    [19, 73.984, 74.002, 74.003, 74.005, 73.997],
    [20, 74.000, 74.010, 74.013, 74.020, 74.003],
    [21, 73.982, 74.001, 74.015, 74.005, 73.996],
    [22, 74.004, 73.999, 73.990, 74.006, 74.009],
    [23, 74.010, 73.989, 73.990, 74.009, 74.014],
    [24, 74.015, 74.008, 73.993, 74.000, 74.010],
    [25, 73.982, 73.984, 73.995, 74.017, 74.013]
]
for r in data:
    ws.append(r)

for col in ['A', 'B', 'C', 'D', 'E', 'F']:
    ws.column_dimensions[col].width = 12

wb.save('/home/ga/Documents/piston_ring_measurements.xlsx')
PYEOF

chown ga:ga "$FILE_PATH"

# Start WPS Spreadsheet
if ! pgrep -f "et " > /dev/null; then
    su - ga -c "DISPLAY=:1 et '$FILE_PATH' &"
    sleep 5
fi

# Maximize and focus WPS Window
for i in {1..15}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "piston_ring_measurements" | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
        DISPLAY=:1 wmctrl -i -a "$WID"
        break
    fi
    sleep 1
done

# Dismiss any stray dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take setup verification screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="