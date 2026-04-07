#!/bin/bash
echo "=== Setting up evaluate_merchant_plant_wholesale_revenue task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/merchant_plant_results.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start time
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Generate statistically realistic 8760 ERCOT LMP price array ($/MWh)
# This mimics actual ERCOT Houston Hub real-time market volatility
echo "Generating realistic ERCOT 8760 hourly LMP dataset..."
cat << 'EOF' > /tmp/generate_lmps.py
import csv
import math
import random

random.seed(42)  # Ensure deterministic but realistic data

filepath = '/home/ga/Documents/SAM_Projects/ercot_hourly_lmp.csv'
with open(filepath, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["LMP_Price_$/MWh"])
    
    for day in range(365):
        # Summer flag (June - August approx)
        is_summer = 151 <= day <= 242
        
        for hour in range(24):
            # Base overnight price
            price = random.uniform(15.0, 25.0)
            
            # Morning ramp (6 AM - 9 AM)
            if 6 <= hour <= 9:
                price += random.uniform(5.0, 15.0)
            
            # Solar depression / Duck curve belly (10 AM - 3 PM)
            if 10 <= hour <= 15:
                # Prices drop, sometimes negative in high solar penetration
                price -= random.uniform(10.0, 25.0)
                
            # Evening peak (4 PM - 8 PM)
            if 16 <= hour <= 20:
                ramp = random.uniform(20.0, 60.0)
                if is_summer:
                    # Summer peak demands
                    ramp += random.uniform(30.0, 100.0)
                    # Scarcity pricing spikes
                    if random.random() < 0.05:
                        ramp += random.uniform(200.0, 800.0)
                price += ramp
                
            # Floor prices to realistic negative bounds
            if price < -20.0:
                price = random.uniform(-20.0, 0.0)
                
            writer.writerow([round(price, 2)])
EOF

python3 /tmp/generate_lmps.py
chown ga:ga /home/ga/Documents/SAM_Projects/ercot_hourly_lmp.csv

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

echo "=== Task setup complete ==="