#!/bin/bash
echo "=== Setting up FAA Wildlife Strike Analysis task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

STRIKES_FILE="/home/ga/Documents/wildlife_strikes.xlsx"
rm -f "$STRIKES_FILE" 2>/dev/null || true

# Generate realistic data based on FAA Wildlife Strike Database
python3 << 'PYEOF'
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

wb = Workbook()

# 1. STRIKES SHEET
ws_strikes = wb.active
ws_strikes.title = 'Strikes'
ws_strikes.append(['Incident_Date', 'Airport_Code', 'Species', 'Aircraft_Type', 'Damage_Level', 'Repair_Cost', 'Other_Cost'])

# Real FAA strike dataset samples (anonymized/excerpted for this task)
strike_data = [
    ['2023-01-15', 'KDEN', 'Horned lark', 'B-737-800', 'None', 0, 0],
    ['2023-01-18', 'KDFW', 'Mourning dove', 'A-321', 'Minor', 15000, 2500],
    ['2023-02-02', 'KJFK', 'Herring gull', 'B-767-300', 'Substantial', 125000, 15000],
    ['2023-02-14', 'KLAX', 'Rock pigeon', 'B-737-700', 'None', 0, 0],
    ['2023-03-05', 'KATL', 'Red-tailed hawk', 'B-757-200', 'Minor', 45000, 5500],
    ['2023-03-12', 'KMIA', 'Turkey vulture', 'A-320', 'Substantial', 85000, 12000],
    ['2023-04-01', 'KDEN', 'Western meadowlark', 'A-319', 'None', 0, 0],
    ['2023-04-18', 'KSEA', 'Bald eagle', 'B-737-900', 'Substantial', 250000, 45000],
    ['2023-05-09', 'KMCO', 'Cattle egret', 'B-737-800', 'Minor', 12000, 0],
    ['2023-05-22', 'KBOS', 'European starling', 'E-190', 'None', 0, 0],
    ['2023-06-11', 'KJFK', 'Osprey', 'B-777-200', 'Minor', 35000, 8000],
    ['2023-06-30', 'KATL', 'Mourning dove', 'CRJ-900', 'None', 0, 0],
    ['2023-07-04', 'KDFW', 'Barn owl', 'A-321', 'None', 0, 1500],
    ['2023-07-15', 'KLAX', 'Gull', 'B-737-800', 'Substantial', 65000, 10000],
    ['2023-08-02', 'KSEA', 'Canada goose', 'B-737-MAX8', 'Substantial', 450000, 60000],
    ['2023-08-19', 'KMIA', 'Black vulture', 'B-767-300', 'Minor', 22000, 4000],
    ['2023-09-05', 'KDEN', 'Swainson hawk', 'A-320', 'Minor', 18000, 0],
    ['2023-09-21', 'KMCO', 'Sandhill crane', 'A-321', 'Substantial', 185000, 25000],
    ['2023-10-10', 'KBOS', 'Great black-backed gull', 'B-737-800', 'Minor', 28000, 5000],
    ['2023-10-31', 'KJFK', 'Snow goose', 'A-350', 'Substantial', 320000, 50000],
]

# Duplicate and shuffle to create a slightly larger dataset (~60 rows)
import random
random.seed(42)
full_data = strike_data * 3
random.shuffle(full_data)

for row in full_data:
    ws_strikes.append(row)

# 2. AIRPORTS SHEET
ws_airports = wb.create_sheet(title='Airports')
ws_airports.append(['Airport_Code', 'Airport_Name', 'City', 'State'])

airports_data = [
    ['KATL', 'Hartsfield-Jackson Atlanta Intl', 'Atlanta', 'GA'],
    ['KBOS', 'Logan Intl', 'Boston', 'MA'],
    ['KDEN', 'Denver Intl', 'Denver', 'CO'],
    ['KDFW', 'Dallas/Fort Worth Intl', 'Dallas', 'TX'],
    ['KJFK', 'John F Kennedy Intl', 'New York', 'NY'],
    ['KLAX', 'Los Angeles Intl', 'Los Angeles', 'CA'],
    ['KMCO', 'Orlando Intl', 'Orlando', 'FL'],
    ['KMIA', 'Miami Intl', 'Miami', 'FL'],
    ['KORD', 'Chicago OHare Intl', 'Chicago', 'IL'],
    ['KSEA', 'Seattle-Tacoma Intl', 'Seattle', 'WA'],
]

for row in airports_data:
    ws_airports.append(row)

# 3. SUMMARY SHEET
ws_summary = wb.create_sheet(title='Summary')
ws_summary.append(['State', 'Total_Strikes', 'Total_Cost', 'Major_Incidents'])

# We only want to summarize a specific set of states
states_to_summarize = ['CO', 'TX', 'NY', 'CA', 'GA', 'FL', 'WA', 'MA', 'IL', 'NJ']
for state in states_to_summarize:
    ws_summary.append([state])

# Formatting Headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9E1F2', end_color='D9E1F2', fill_type='solid')

for ws in wb.worksheets:
    for cell in ws[1]:
        cell.font = header_font
        cell.fill = header_fill

# Adjust column widths
ws_strikes.column_dimensions['A'].width = 12
ws_strikes.column_dimensions['B'].width = 14
ws_strikes.column_dimensions['C'].width = 25
ws_strikes.column_dimensions['D'].width = 15
ws_strikes.column_dimensions['E'].width = 15
ws_strikes.column_dimensions['F'].width = 12
ws_strikes.column_dimensions['G'].width = 12
ws_strikes.column_dimensions['H'].width = 10
ws_strikes.column_dimensions['I'].width = 15
ws_strikes.column_dimensions['J'].width = 15

wb.save('/home/ga/Documents/wildlife_strikes.xlsx')
PYEOF

chown ga:ga "$STRIKES_FILE"

# Start WPS Spreadsheet if not running, focused and maximized
if ! pgrep -f "et" > /dev/null; then
    su - ga -c "DISPLAY=:1 et '$STRIKES_FILE' &"
    sleep 5
fi

# Wait for window and maximize it
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -i "wildlife_strikes"; then
        DISPLAY=:1 wmctrl -r "wildlife_strikes" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "wildlife_strikes" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="