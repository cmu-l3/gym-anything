#!/bin/bash
# Setup script for climate_anomaly_css_bars task

echo "=== Setting up Climate Anomaly CSS Bars Task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing files to prevent gaming
rm -f /home/ga/Documents/generate_climate_bars.py 2>/dev/null || true
rm -f /home/ga/Documents/climate_bars.html 2>/dev/null || true
rm -f /home/ga/Documents/gistemp_anomalies.csv 2>/dev/null || true

# Record task start timestamp for mtime validation
date +%s > /tmp/climate_bars_start_ts
chmod 666 /tmp/climate_bars_start_ts

# Generate realistic NASA GISTEMP dataset
echo "Generating NASA GISTEMP historical dataset..."
cat << 'EOF' > /tmp/gen_csv.py
import random
import os

filepath = '/home/ga/Documents/gistemp_anomalies.csv'
with open(filepath, 'w') as f:
    f.write("Source,Year,Mean\n")
    for year in range(1880, 2021):
        if year == 1900: 
            mean = -0.09
        elif year == 1950: 
            mean = -0.17
        elif year == 2000: 
            mean = 0.42
        elif year == 2016: 
            mean = 0.99
        else:
            # Generate realistic baseline warming curve
            base = -0.2 if year < 1930 else (0.0 if year < 1980 else 0.5)
            base += (year - 1980) * 0.015 if year >= 1980 else 0
            mean = round(base + random.uniform(-0.15, 0.15), 2)
        
        f.write(f"GISTEMP,{year},{mean}\n")

os.chmod(filepath, 0o644)
EOF

# Run as ga user
su - ga -c "python3 /tmp/gen_csv.py"
rm -f /tmp/gen_csv.py

# Close any open activities to return to the Sugar home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 2
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 2

# Verify Sugar session is running
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, attempting to restart..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/climate_task_start.png" 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Dataset created at /home/ga/Documents/gistemp_anomalies.csv"
echo "Agent must write Python script to generate climate_bars.html with dynamic CSS styling."