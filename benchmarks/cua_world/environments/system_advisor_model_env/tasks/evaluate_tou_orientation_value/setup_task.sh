#!/bin/bash
echo "=== Setting up evaluate_tou_orientation_value task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/tou_orientation_value.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/.gt_values.json 2>/dev/null || true

# Clear any cached Python scripts from previous task runs
rm -f /home/ga/*.py /home/ga/pv_*.py /home/ga/sam_*.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true

# Record task start time
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure weather data directory is accessible
if [ ! -f "/home/ga/SAM_Weather_Data/phoenix_az_tmy.csv" ]; then
    echo "WARNING: Phoenix weather file not found at expected path. Attempting to link..."
    mkdir -p /home/ga/SAM_Weather_Data
    find /opt/SAM -name "*phoenix*" -o -name "*Phoenix*" | head -1 | xargs -I {} cp {} /home/ga/SAM_Weather_Data/phoenix_az_tmy.csv
fi

# ==============================================================================
# Generate Ground Truth Data (Hidden from agent)
# ==============================================================================
echo "Generating ground truth validation data..."
cat << 'EOF' > /tmp/generate_gt.py
import json
import os

try:
    import PySAM.Pvwattsv8 as pvwatts
    
    def run_sim(azimuth):
        sys = pvwatts.new()
        sys.SolarResource.solar_resource_file = "/home/ga/SAM_Weather_Data/phoenix_az_tmy.csv"
        sys.SystemDesign.system_capacity = 500
        sys.SystemDesign.dc_ac_ratio = 1.2
        sys.SystemDesign.array_type = 1
        sys.SystemDesign.tilt = 20
        sys.SystemDesign.azimuth = azimuth
        sys.SystemDesign.losses = 14
        sys.SystemDesign.inv_eff = 96
        
        sys.execute()
        
        gen = sys.Outputs.gen
        annual_energy = sys.Outputs.annual_energy
        
        # TOU Calculation
        days_in_month = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        peak_months = [6, 7, 8, 9] # June-Sep
        peak_hours = [16, 17, 18] # 16:00, 17:00, 18:00
        
        total_value = 0.0
        hour_of_year = 0
        
        for m, days in enumerate(days_in_month):
            month = m + 1
            for d in range(days):
                for h in range(24):
                    power_kw = gen[hour_of_year]
                    if month in peak_months and h in peak_hours:
                        price = 0.35
                    else:
                        price = 0.08
                    total_value += power_kw * price
                    hour_of_year += 1
                    
        return annual_energy, total_value

    south_energy, south_value = run_sim(180)
    west_energy, west_value = run_sim(270)
    higher = "South" if south_value > west_value else "West"
    
    gt = {
        "gt_success": True,
        "south_annual_energy_kwh": south_energy,
        "west_annual_energy_kwh": west_energy,
        "south_annual_value_usd": south_value,
        "west_annual_value_usd": west_value,
        "higher_value_orientation": higher
    }
except Exception as e:
    gt = {
        "gt_success": False,
        "error": str(e)
    }

with open("/tmp/.gt_values.json", "w") as f:
    json.dump(gt, f)
EOF

# Run ground truth generation silently
python3 /tmp/generate_gt.py 2>/dev/null
rm /tmp/generate_gt.py

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="