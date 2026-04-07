#!/bin/bash
echo "=== Setting up compute_pv_merchant_revenue task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/merchant_revenue_analysis.json 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/caiso_sp15_2022_lmp.csv 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/expected_lmp.txt 2>/dev/null || true

# Clear cached Python scripts
rm -f /home/ga/*.py 2>/dev/null || true

# Record task start time
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
mkdir -p /home/ga/SAM_Weather_Data

# Generate realistic 8760 LMP price dataset derived from the solar/temp profile
# This creates deterministic, realistic data with negative correlation to solar output (duck curve)
cat << 'EOF' > /tmp/generate_lmp.py
import csv
import os

weather_path = '/home/ga/SAM_Weather_Data/phoenix_az_tmy.csv'
out_path = '/home/ga/Documents/SAM_Projects/caiso_sp15_2022_lmp.csv'

# Generate synthetic but highly realistic LMP data based on physical weather
try:
    with open(weather_path, 'r') as f:
        lines = f.readlines()
        
    # Extract headers to find GHI and Tdry
    headers = lines[1].strip().split(',')
    ghi_idx = headers.index('GHI') if 'GHI' in headers else 7
    tdry_idx = headers.index('Tdry') if 'Tdry' in headers else 8
    
    out_lines = [("Hour", "LMP")]
    total_lmp = 0.0
    count = 0
    
    # Process 8760 rows of data (skipping 2 header rows)
    for i, line in enumerate(lines[2:8762]):
        if not line.strip(): continue
        parts = line.strip().split(',')
        if len(parts) <= max(ghi_idx, tdry_idx): continue
        
        try:
            ghi = float(parts[ghi_idx])
            tdry = float(parts[tdry_idx])
            hour_of_day = i % 24
            
            # Base price + temperature impact (AC demand) - solar oversupply + evening peak
            lmp = 25.0 + (tdry * 1.2) - (ghi * 0.045)
            
            # Evening ramp up (Duck curve head)
            if 17 <= hour_of_day <= 20:
                lmp += 45.0
                
            lmp = max(0.0, lmp) # Clip at $0/MWh for simplicity
            
            out_lines.append((i+1, round(lmp, 2)))
            total_lmp += round(lmp, 2)
            count += 1
        except Exception:
            pass
            
    # Calculate exact average
    avg_lmp = total_lmp / count if count > 0 else 0
    
    with open(out_path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerows(out_lines)
        
    with open('/tmp/expected_lmp.txt', 'w') as f:
        f.write(str(round(avg_lmp, 2)))
        
except Exception as e:
    print(f"Error generating LMP data: {e}")
EOF

python3 /tmp/generate_lmp.py
chown -R ga:ga /home/ga/Documents/SAM_Projects/caiso_sp15_2022_lmp.csv

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

echo "=== Task setup complete ==="