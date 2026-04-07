#!/bin/bash
set -e
echo "=== Setting up NYC Restaurant Inspection Audit task ==="

FILE_PATH="/home/ga/Documents/nyc_inspections_audit.xlsx"

# Generate the workbook using realistic embedded NYC open data
python3 << 'PYEOF'
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

wb = Workbook()

# 1. Violations Log Sheet
ws_log = wb.active
ws_log.title = "Violations_Log"
ws_log.append(["CAMIS", "DBA", "InspectionDate", "ViolationCode", "CriticalFlag", "Points"])

data_log = [
    [40356018, "RIVIERA CATERERS", "2022-05-16", "10F", "N", 2],
    [40356018, "RIVIERA CATERERS", "2022-05-16", "08A", "N", 3],
    [40356018, "RIVIERA CATERERS", "2022-05-16", "04L", "Y", 9],
    [40356151, "BRUNOS ON THE BOULEVARD", "2021-08-19", "04L", "Y", 10],
    [40356151, "BRUNOS ON THE BOULEVARD", "2021-08-19", "08A", "N", 5],
    [40356151, "BRUNOS ON THE BOULEVARD", "2021-08-19", "02G", "Y", 15],
    [40356151, "BRUNOS ON THE BOULEVARD", "2021-08-19", "04N", "Y", 8],
    [40356483, "WILKEN'S FINE FOOD", "2022-06-03", "02B", "Y", 10],
    [40356483, "WILKEN'S FINE FOOD", "2022-06-03", "04L", "Y", 9],
    [40356483, "WILKEN'S FINE FOOD", "2022-06-03", "06A", "Y", 5],
    [40356731, "TASTE THE TROPICS ICE CREAM", "2022-06-15", "04L", "Y", 8],
    [40356731, "TASTE THE TROPICS ICE CREAM", "2022-06-15", "08A", "N", 3],
    [40356731, "TASTE THE TROPICS ICE CREAM", "2022-06-15", "10B", "N", 2],
    [40359705, "NATHAN'S FAMOUS", "2022-08-22", "04L", "Y", 12],
    [40359705, "NATHAN'S FAMOUS", "2022-08-22", "06C", "Y", 6],
    [40360045, "SEACREST DINER", "2022-01-26", "04L", "Y", 7],
    [40360045, "SEACREST DINER", "2022-01-26", "08A", "N", 3],
    [40360045, "SEACREST DINER", "2022-01-26", "10F", "N", 2],
    [40360076, "CARVEL ICE CREAM", "2022-08-25", "08C", "N", 2],
    [40360076, "CARVEL ICE CREAM", "2022-08-25", "10F", "N", 3],
    [40361618, "SAL FORTE'S", "2021-12-16", "04L", "Y", 9],
    [40361618, "SAL FORTE'S", "2021-12-16", "06A", "Y", 7],
    [40361618, "SAL FORTE'S", "2021-12-16", "10B", "N", 3],
    [40361618, "SAL FORTE'S", "2021-12-16", "10F", "N", 2],
    [40362274, "ANGELIKA FILM CENTER", "2022-07-27", "04L", "Y", 8],
    [40362274, "ANGELIKA FILM CENTER", "2022-07-27", "08A", "N", 3],
    [40362274, "ANGELIKA FILM CENTER", "2022-07-27", "10F", "N", 2],
    [40362432, "HOPE PIZZA RESTAURANT", "2022-05-24", "04L", "Y", 11],
    [40362432, "HOPE PIZZA RESTAURANT", "2022-05-24", "06C", "Y", 5],
    [40362432, "HOPE PIZZA RESTAURANT", "2022-05-24", "10F", "N", 2]
]
for row in data_log:
    ws_log.append(row)

# 2. Fine Master Sheet
ws_fines = wb.create_sheet("Fine_Master")
ws_fines.append(["ViolationCode", "BaseFine"])
fines_data = [
    ["02B", 300], ["02G", 250], ["04L", 400], ["04N", 200], ["06A", 200],
    ["06C", 300], ["08A", 150], ["08C", 100], ["10B", 200], ["10F", 150]
]
for row in fines_data:
    ws_fines.append(row)

# 3. Inspection Rollup Sheet
ws_rollup = wb.create_sheet("Inspection_Rollup")
ws_rollup.append(["CAMIS", "DBA", "InspectionDate"])
rollups = []
seen = set()
for row in data_log:
    key = (row[0], row[1], row[2])
    if key not in seen:
        seen.add(key)
        rollups.append(key)

for r in rollups:
    ws_rollup.append(list(r))

# Styling
header_font = Font(bold=True)
header_fill = PatternFill(start_color="D9E1F2", end_color="D9E1F2", fill_type="solid")
for ws in wb.worksheets:
    for cell in ws[1]:
        cell.font = header_font
        cell.fill = header_fill

ws_log.column_dimensions['A'].width = 12
ws_log.column_dimensions['B'].width = 30
ws_log.column_dimensions['C'].width = 15
ws_rollup.column_dimensions['A'].width = 12
ws_rollup.column_dimensions['B'].width = 30
ws_rollup.column_dimensions['C'].width = 15

wb.save("$FILE_PATH")
PYEOF

chown ga:ga "$FILE_PATH"

# CRITICAL: Record task start time AFTER generating the file so we can accurately detect modification
sleep 1
date +%s > /tmp/task_start_time.txt

# Start WPS Spreadsheet
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$FILE_PATH' &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "nyc_inspections_audit"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "nyc_inspections_audit" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "nyc_inspections_audit" 2>/dev/null || true

# Dismiss WPS startup tips if any
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="