#!/bin/bash
set -e
echo "=== Setting up fleet_fuel_analysis task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

FILE_PATH="/home/ga/Documents/fleet_fuel_data.xlsx"
rm -f "$FILE_PATH" 2>/dev/null || true

# Generate realistic data using Python and OpenPyXL
python3 << 'PYEOF'
import random
import datetime
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()

# 1. Create Vehicles Sheet
ws_vehicles = wb.active
ws_vehicles.title = "Vehicles"

vehicle_headers = ["VehicleID", "Year", "Make", "Model", "FuelType", "EPA_City_MPG", "EPA_Hwy_MPG", "EPA_Combined_MPG"]
ws_vehicles.append(vehicle_headers)

vehicles_data = [
    ("V001", 2023, "Ford", "F-150", "Gasoline", 20, 24, 22),
    ("V002", 2023, "Chevrolet", "Express 2500", "Gasoline", 15, 19, 16),
    ("V003", 2023, "Ram", "1500", "Gasoline", 20, 25, 23),
    ("V004", 2023, "Ford", "Transit", "Gasoline", 15, 19, 17),
    ("V005", 2023, "Toyota", "Camry", "Gasoline", 28, 39, 32),
    ("V006", 2023, "Honda", "Civic", "Gasoline", 31, 40, 35),
    ("V007", 2023, "Ford", "Escape", "Gasoline", 27, 33, 30),
    ("V008", 2023, "Chevrolet", "Silverado 1500", "Gasoline", 19, 22, 21),
    ("V009", 2023, "Nissan", "NV200", "Gasoline", 24, 26, 25),
    ("V010", 2023, "Mercedes-Benz", "Sprinter", "Diesel", 19, 22, 20),
    ("V011", 2022, "Ford", "E-350", "Gasoline", 11, 15, 13),
    ("V012", 2023, "Toyota", "Tacoma", "Gasoline", 20, 23, 21),
    ("V013", 2023, "Chevrolet", "Colorado", "Gasoline", 19, 25, 22),
    ("V014", 2023, "Ford", "Maverick", "Gasoline", 40, 33, 37),
    ("V015", 2023, "Ram", "ProMaster", "Gasoline", 16, 21, 18),
]

for v in vehicles_data:
    ws_vehicles.append(v)

# Format Headers
header_fill = PatternFill(start_color='D9E1F2', end_color='D9E1F2', fill_type='solid')
for cell in ws_vehicles[1]:
    cell.font = Font(bold=True)
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

for col in ['A', 'C', 'D', 'E']:
    ws_vehicles.column_dimensions[col].width = 15

# 2. Create FuelLog Sheet
ws_log = wb.create_sheet(title="FuelLog")
log_headers = ["Date", "VehicleID", "MilesDriven", "Gallons", "PricePerGallon"]
ws_log.append(log_headers)

random.seed(42) # Deterministic data generation
start_date = datetime.date(2024, 1, 1)

# Generate 150 entries ~ 10 per vehicle
logs = []
for _ in range(150):
    vid = random.choice(vehicles_data)
    v_id = vid[0]
    epa = vid[7]
    
    # Introduce maintenance issues for V002 and V011 (degrade efficiency by 25%)
    if v_id in ["V002", "V011"]:
        actual_mpg = epa * random.uniform(0.70, 0.78)
    # V014 performs incredibly well
    elif v_id == "V014":
        actual_mpg = epa * random.uniform(0.98, 1.05)
    else:
        actual_mpg = epa * random.uniform(0.85, 0.95)
        
    gallons = round(random.uniform(10.0, 25.0), 1)
    miles = round(gallons * actual_mpg, 1)
    
    # Random date within Q1
    days_add = random.randint(0, 89)
    log_date = start_date + datetime.timedelta(days=days_add)
    
    price = round(random.uniform(3.15, 3.85), 2)
    
    logs.append({
        "date": log_date,
        "vid": v_id,
        "miles": miles,
        "gallons": gallons,
        "price": price
    })

# Sort by date
logs.sort(key=lambda x: x["date"])

for log in logs:
    ws_log.append([log["date"].strftime("%m/%d/%Y"), log["vid"], log["miles"], log["gallons"], log["price"]])

for cell in ws_log[1]:
    cell.font = Font(bold=True)
    cell.fill = header_fill

ws_log.column_dimensions['A'].width = 12
ws_log.column_dimensions['B'].width = 12
ws_log.column_dimensions['C'].width = 12
ws_log.column_dimensions['D'].width = 10
ws_log.column_dimensions['E'].width = 14

wb.save('/home/ga/Documents/fleet_fuel_data.xlsx')
PYEOF

chown ga:ga "$FILE_PATH"

# Ensure application is running
echo "Starting WPS Spreadsheet..."
if ! pgrep -f "et " > /dev/null; then
    su - ga -c "DISPLAY=:1 et '$FILE_PATH' > /dev/null 2>&1 &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "fleet_fuel_data"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "fleet_fuel_data" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "fleet_fuel_data" 2>/dev/null || true

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="