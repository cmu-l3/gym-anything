#!/bin/bash
echo "=== Setting up flight_delay_liability task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

FLIGHT_FILE="/home/ga/Documents/flight_data.xlsx"
rm -f "$FLIGHT_FILE" 2>/dev/null || true

# Generate realistic flight data dataset using Python
python3 << 'PYEOF'
import random
import datetime
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

wb = Workbook()
ws = wb.active
ws.title = "Flights"

# Headers
headers = ['DATE', 'AIRLINE', 'FLIGHT_NUMBER', 'ORIGIN', 'DESTINATION', 'DISTANCE', 'DEPARTURE_DELAY', 'ARRIVAL_DELAY', 'CANCELLED']
ws.append(headers)

# Formatting headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color="D9D9D9", end_color="D9D9D9", fill_type="solid")
for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill

airlines = ['AA', 'DL', 'UA', 'WN', 'B6', 'AS', 'NK']
airports = ['JFK', 'LAX', 'ORD', 'DFW', 'DEN', 'ATL', 'SFO', 'SEA', 'LAS', 'MCO', 'MIA', 'BOS']

# Generate 10000 realistic records
random.seed(42) # Reproducible randomness
start_date = datetime.date(2023, 1, 1)

for i in range(10000):
    date = start_date + datetime.timedelta(days=random.randint(0, 364))
    airline = random.choice(airlines)
    flight_num = random.randint(100, 9999)
    origin, dest = random.sample(airports, 2)
    distance = random.randint(200, 2800)
    
    # Delays and Cancellations
    is_cancelled = 1 if random.random() < 0.02 else 0
    
    if is_cancelled:
        dep_delay = random.randint(0, 300)
        arr_delay = None
    else:
        # 70% on time or early, 20% delayed < 120m, 10% severe delay
        status_roll = random.random()
        if status_roll < 0.7:
            dep_delay = random.randint(-15, 15)
        elif status_roll < 0.9:
            dep_delay = random.randint(16, 119)
        else:
            dep_delay = random.randint(120, 400)
            
        # Arrival delay correlates with dep delay
        arr_delay = dep_delay + random.randint(-20, 30)
    
    ws.append([
        date.strftime("%m/%d/%Y"),
        airline,
        flight_num,
        origin,
        dest,
        distance,
        dep_delay,
        arr_delay if arr_delay is not None else "",
        is_cancelled
    ])

# Freeze top row
ws.freeze_panes = "A2"

# Auto-adjust some widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 10
ws.column_dimensions['C'].width = 16
ws.column_dimensions['D'].width = 10
ws.column_dimensions['E'].width = 14
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 18
ws.column_dimensions['H'].width = 16
ws.column_dimensions['I'].width = 12

wb.save('/home/ga/Documents/flight_data.xlsx')
print("Successfully generated 10,000 row dataset.")
PYEOF

# Fix permissions
chown ga:ga "$FLIGHT_FILE" 2>/dev/null || true

# Make sure WPS is not running initially to have a clean slate
pkill -x et 2>/dev/null || true
sleep 1

# Launch WPS Spreadsheet with the file
echo "Launching WPS Spreadsheet..."
su - ga -c "export DISPLAY=:1; et '$FLIGHT_FILE' &"

# Wait for application to open
for i in {1..20}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "flight_data"; then
        echo "WPS Spreadsheet window detected."
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="