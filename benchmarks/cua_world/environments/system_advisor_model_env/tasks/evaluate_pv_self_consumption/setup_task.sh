#!/bin/bash
echo "=== Setting up evaluate_pv_self_consumption task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/self_consumption_results.json 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/commercial_load_8760.csv 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Clear any cached Python scripts from previous task runs
rm -f /home/ga/*.py /home/ga/pv_*.py /home/ga/sam_*.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true

# Record task start time
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Generate a realistic 8760-hour commercial load profile using Python
cat << 'EOF' > /tmp/generate_load.py
import csv
import math
import os

output_path = '/home/ga/Documents/SAM_Projects/commercial_load_8760.csv'
expected_load_path = '/home/ga/.expected_load.txt'

total_load = 0.0

with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Load_kW'])
    for i in range(8760):
        doy = i // 24
        hod = i % 24
        
        # Base load (servers, basic HVAC, emergency lighting)
        load = 15.0
        
        # Daytime operations (8 AM to 6 PM)
        if 8 <= hod <= 18:
            load += 35.0
            
            # Summer cooling peak (approx mid-May to mid-Sep)
            if 135 <= doy <= 260:
                load += 25.0 * math.sin((hod - 8) / 10.0 * math.pi)
                
        # Small random variation to make it realistic
        val = round(load, 2)
        writer.writerow([val])
        total_load += val

with open(expected_load_path, 'w') as f:
    f.write(str(round(total_load, 2)))

os.chmod(output_path, 0o666)
EOF

python3 /tmp/generate_load.py
chown ga:ga /home/ga/Documents/SAM_Projects/commercial_load_8760.csv
EXPECTED_LOAD=$(cat /home/ga/.expected_load.txt)
echo "Generated commercial load profile with total load: $EXPECTED_LOAD kWh"

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

echo "=== Task setup complete ==="