#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Airline OTP Analysis Task ==="

# Record task start timestamp for anti-gaming
echo $(date +%s) > /tmp/task_start_time.txt

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/pnw_flight_ops_q3_2024.csv"

# Generate the synthetic but highly realistic dataset
cat > /tmp/create_flight_data.py << 'PYEOF'
import csv
import random
from datetime import datetime, timedelta
import sys

random.seed(2024)

routes = [
    ("SEA", "PDX", 129), ("PDX", "SEA", 129),
    ("SEA", "SFO", 679), ("SFO", "SEA", 679),
    ("SEA", "BOI", 399), ("BOI", "SEA", 399),
    ("SEA", "GEG", 224), ("GEG", "SEA", 224),
    ("PDX", "SFO", 550), ("SFO", "PDX", 550),
    ("PDX", "MFR", 222), ("MFR", "PDX", 222)
]

start_date = datetime(2024, 7, 1)
end_date = datetime(2024, 9, 30)
days_in_q3 = (end_date - start_date).days + 1

flights = []
flight_num = 1000

for i in range(500):
    day_offset = random.randint(0, days_in_q3 - 1)
    f_date = start_date + timedelta(days=day_offset)
    
    # Route selection bias to ensure enough representation for specific pairs
    if i < 40: route = ("SEA", "BOI", 399)
    elif i < 80: route = ("GEG", "SEA", 224)
    else: route = random.choice(routes)
    
    origin, dest, dist = route
    
    # Base delay probability
    base_delay_prob = 0.20
    if f_date.month == 7: base_delay_prob += 0.05
    elif f_date.month == 9: base_delay_prob -= 0.05
    
    if origin == "SEA" and dest == "BOI": base_delay_prob += 0.15 # Worst performer
    if origin == "GEG" and dest == "SEA": base_delay_prob -= 0.10 # Best performer
    
    is_cancelled = random.random() < 0.032
    is_delayed = not is_cancelled and random.random() < base_delay_prob
    
    crs_dep_hour = random.randint(6, 21)
    crs_dep_min = random.choice([0, 15, 30, 45])
    
    dep_time_str = f"{crs_dep_hour:02d}{crs_dep_min:02d}"
    flight_duration_mins = int(dist / 6.0) # rough estimate
    
    arr_hour = (crs_dep_hour + (crs_dep_min + flight_duration_mins) // 60) % 24
    arr_min = (crs_dep_min + flight_duration_mins) % 60
    crs_arr_time_str = f"{arr_hour:02d}{arr_min:02d}"
    
    dep_delay = 0
    arr_delay = 0
    carrier, weather, nas, security, late = 0, 0, 0, 0, 0
    cancelled_val = 0
    cancel_code = ""
    
    if is_cancelled:
        cancelled_val = 1
        cancel_code = random.choice(["A", "B", "C"])
        act_dep_time = ""
        act_arr_time = ""
    elif is_delayed:
        arr_delay = random.randint(15, 120)
        dep_delay = arr_delay - random.randint(-5, 5)
        
        # Distribute delay causes
        delay_type_rand = random.random()
        if delay_type_rand < 0.35: late = arr_delay
        elif delay_type_rand < 0.65: carrier = arr_delay
        elif delay_type_rand < 0.90: nas = arr_delay
        elif delay_type_rand < 0.99: weather = arr_delay
        else: security = arr_delay
        
        act_arr_mins_total = arr_hour * 60 + arr_min + arr_delay
        act_arr_h = (act_arr_mins_total // 60) % 24
        act_arr_m = act_arr_mins_total % 60
        act_arr_time = f"{act_arr_h:02d}{act_arr_m:02d}"
        
        act_dep_mins_total = crs_dep_hour * 60 + crs_dep_min + dep_delay
        act_dep_h = (act_dep_mins_total // 60) % 24
        act_dep_m = act_dep_mins_total % 60
        act_dep_time = f"{act_dep_h:02d}{act_dep_m:02d}"
    else:
        arr_delay = random.randint(-15, 14)
        dep_delay = arr_delay - random.randint(-5, 5)
        
        act_arr_mins_total = arr_hour * 60 + arr_min + arr_delay
        act_arr_h = (act_arr_mins_total // 60) % 24
        act_arr_m = act_arr_mins_total % 60
        act_arr_time = f"{act_arr_h:02d}{act_arr_m:02d}"
        
        act_dep_mins_total = crs_dep_hour * 60 + crs_dep_min + dep_delay
        act_dep_h = (act_dep_mins_total // 60) % 24
        act_dep_m = act_dep_mins_total % 60
        act_dep_time = f"{act_dep_h:02d}{act_dep_m:02d}"

    flights.append({
        "FlightDate": f_date.strftime("%Y-%m-%d"),
        "FlightNum": flight_num + i,
        "Origin": origin,
        "Dest": dest,
        "CRSDepTime": dep_time_str,
        "DepTime": act_dep_time,
        "DepDelayMinutes": dep_delay if not is_cancelled else "",
        "CRSArrTime": crs_arr_time_str,
        "ArrTime": act_arr_time,
        "ArrDelayMinutes": arr_delay if not is_cancelled else "",
        "CarrierDelay": carrier if arr_delay >= 15 else 0,
        "WeatherDelay": weather if arr_delay >= 15 else 0,
        "NASDelay": nas if arr_delay >= 15 else 0,
        "SecurityDelay": security if arr_delay >= 15 else 0,
        "LateAircraftDelay": late if arr_delay >= 15 else 0,
        "Distance": dist,
        "Cancelled": cancelled_val,
        "CancellationCode": cancel_code,
        "DayOfWeek": f_date.isoweekday()
    })

with open(sys.argv[1], 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=flights[0].keys())
    writer.writeheader()
    writer.writerows(flights)
PYEOF

python3 /tmp/create_flight_data.py "$CSV_PATH"
chown ga:ga "$CSV_PATH"

# Launch ONLYOFFICE with the CSV file
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' > /tmp/onlyoffice_launch.log 2>&1 &"

# Wait for window to appear
wait_for_window "ONLYOFFICE" 30
sleep 5

# Focus and maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
WID=$(DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    focus_window "$WID"
fi
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="