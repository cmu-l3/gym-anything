#!/bin/bash
echo "=== Setting up evaluate_custom_weather_data_pv_yield task ==="

# Record task start time
date +%s > /home/ga/.task_start_time

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/weather_comparison_results.json 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/raw_logger_data_2023.csv 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/*.py 2>/dev/null || true

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Find a suitable TMY weather file to act as the base for our realistic "datalogger" file
TMY_FILE=$(find /opt/SAM -name "*phoenix*.csv" -o -name "*Phoenix*.csv" 2>/dev/null | head -1)
if [ -z "$TMY_FILE" ]; then
    TMY_FILE=$(find /opt/SAM -name "*.csv" | grep -i "tmy" | head -1)
fi
echo "$TMY_FILE" > /tmp/tmy_file_used.txt

if [ -n "$TMY_FILE" ] && [ -f "$TMY_FILE" ]; then
    echo "Found TMY file: $TMY_FILE"
    
    # Python script to convert SAM CSV to Datalogger CSV format
    # Multiplies irradiance by 0.95 to simulate a realistically slightly lower-yield year 
    # and prevent the agent from just copying the TMY result.
    cat << 'EOF' > /tmp/generate_logger_data.py
import sys, csv, datetime

input_file = sys.argv[1]
output_file = sys.argv[2]

with open(input_file, 'r') as f:
    lines = f.readlines()

headers = lines[1].strip().split(',')
def get_idx(name): 
    return headers.index(name) if name in headers else -1

y_idx = get_idx('Year')
m_idx = get_idx('Month')
d_idx = get_idx('Day')
h_idx = get_idx('Hour')
min_idx = get_idx('Minute')

ghi_idx, dni_idx, dhi_idx = get_idx('GHI'), get_idx('DNI'), get_idx('DHI')
temp_idx, wspd_idx = get_idx('Tdry'), get_idx('Wspd')

with open(output_file, 'w', newline='') as f:
    writer = csv.writer(f)
    # Write datalogger headers
    writer.writerow(['TIMESTAMP', 'GHI_W_m2_Avg', 'DNI_W_m2_Avg', 'DHI_W_m2_Avg', 'Air_Temp_C_Avg', 'Wind_Speed_m_s_Avg'])
    
    for row in csv.reader(lines[2:]):
        if not row or len(row) < 5: continue
        try:
            month = int(row[m_idx])
            day = int(row[d_idx])
            hour_val = int(row[h_idx])
            minute_val = int(row[min_idx])
            
            # Construct a proper timestamp
            base_date = datetime.datetime(2023, month, day)
            
            # Handling SAM hour conventions (often 1-24 or 0-23)
            if 0 < hour_val <= 24:
                dt = base_date + datetime.timedelta(hours=hour_val-1, minutes=minute_val)
            else:
                dt = base_date + datetime.timedelta(hours=hour_val, minutes=minute_val)
                
            ts = dt.strftime('%Y-%m-%d %H:%M:%S')
            
            # Inject a realistic 5% drop in irradiance to differentiate from the baseline TMY
            ghi = float(row[ghi_idx]) * 0.95 if ghi_idx >= 0 else 0
            dni = float(row[dni_idx]) * 0.95 if dni_idx >= 0 else 0
            dhi = float(row[dhi_idx]) * 0.95 if dhi_idx >= 0 else 0
            temp = float(row[temp_idx]) if temp_idx >= 0 else 20.0
            wspd = float(row[wspd_idx]) if wspd_idx >= 0 else 0.0
            
            writer.writerow([ts, round(ghi, 2), round(dni, 2), round(dhi, 2), temp, wspd])
        except Exception as e:
            continue
EOF

    python3 /tmp/generate_logger_data.py "$TMY_FILE" "/home/ga/Documents/SAM_Projects/raw_logger_data_2023.csv"
    chown ga:ga "/home/ga/Documents/SAM_Projects/raw_logger_data_2023.csv"
    echo "Generated raw_logger_data_2023.csv"
else
    echo "WARNING: Could not find TMY file to generate logger data."
fi

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take initial screenshot showing environment setup
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="