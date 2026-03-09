#!/bin/bash
set -e
echo "=== Setting up Fuel Cell Stability Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directory
mkdir -p /home/ga/Desktop/PowerBITasks

# Generate realistic Fuel Cell Data using Python
# (Simulating ~3000s of 1Hz data with Gaussian noise around 0.7V)
cat > /tmp/generate_data.py << 'EOF'
import csv
import random
import datetime
import math

start_time = datetime.datetime(2023, 10, 1, 8, 0, 0)
base_voltage = 0.72
current_density = 1.5 # A/cm2
temp_base = 65.0 # Celsius

with open('/home/ga/Desktop/PowerBITasks/fuel_cell_voltage.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Timestamp', 'Stack_Voltage', 'Current_Density', 'Inlet_Temp'])
    
    for i in range(3000):
        t = start_time + datetime.timedelta(seconds=i)
        
        # Add some realistic noise and slight drift
        noise = random.gauss(0, 0.015)
        drift = -0.000005 * i # Very slow degradation
        voltage = base_voltage + drift + noise
        
        # Temp fluctuates slightly
        temp = temp_base + random.gauss(0, 0.5)
        
        writer.writerow([t.strftime('%Y-%m-%d %H:%M:%S'), f"{voltage:.4f}", current_density, f"{temp:.1f}"])

print("Generated fuel_cell_voltage.csv with 3000 rows")
EOF

python3 /tmp/generate_data.py

# Ensure Power BI is running and ready
echo "Checking Power BI status..."
if ! pgrep -f "PBIDesktop" > /dev/null; then
    echo "Starting Power BI Desktop..."
    su - ga -c "DISPLAY=:1 /usr/bin/PBIDesktop &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Power BI Desktop"; then
            echo "Power BI window detected"
            break
        fi
        sleep 1
    done
    sleep 10 # Wait for splash screen to clear
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Power BI Desktop" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Power BI Desktop" 2>/dev/null || true

# Dismiss startup dialog (ESC usually works for the login/splash prompt)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="