#!/bin/bash
# Do NOT use set -e
echo "=== Setting up snells_law_optics_lab task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents

# Remove any pre-existing files to ensure agent creates them fresh
rm -f /home/ga/Documents/calculate_n.py 2>/dev/null || true
rm -f /home/ga/Documents/optics_report.odt 2>/dev/null || true

# Generate the experimental data (Crown Glass, n=1.52)
# We add tiny random noise to the data to simulate a real lab experiment,
# but guarantee the average will round precisely to 1.52.
python3 << 'PYEOF'
import math
import random

target_n = 1.52
angles_i = [10, 20, 30, 40, 50, 60, 70, 80]
csv_path = '/home/ga/Documents/optics_data.csv'

with open(csv_path, 'w') as f:
    f.write("theta_i,theta_r\n")
    for a in angles_i:
        rad_i = math.radians(a)
        sin_r = math.sin(rad_i) / target_n
        rad_r = math.asin(sin_r)
        deg_r = math.degrees(rad_r)
        # Add tiny noise (between -0.01 and +0.01)
        noise = random.uniform(-0.01, 0.01)
        deg_r_noisy = deg_r + noise
        f.write(f"{a},{deg_r_noisy:.2f}\n")
PYEOF

chown -R ga:ga /home/ga/Documents

# Record task start timestamp for mtime validation
date +%s > /tmp/snells_law_start_ts
chmod 666 /tmp/snells_law_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Verify Sugar home view is running
if ! pgrep -f "jarabe.main" > /dev/null 2>&1; then
    echo "Sugar session not found, restarting..."
    systemctl restart gdm 2>/dev/null || true
    sleep 15
fi

# Take a verification screenshot of the initial state
su - ga -c "$SUGAR_ENV scrot /tmp/optics_task_start.png" 2>/dev/null || true

echo "=== snells_law_optics_lab task setup complete ==="
echo "Data generated at /home/ga/Documents/optics_data.csv"
echo "Agent must calculate n, write python script, and create ODT report."