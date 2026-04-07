#!/bin/bash
set -euo pipefail

echo "=== Setting up Space Debris Conjunction Assessment Task ==="

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
    cleanup_temp_files 2>/dev/null || true
    kill_onlyoffice ga 2>/dev/null || true
else
    pkill -f "onlyoffice-desktopeditors" 2>/dev/null || true
fi
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/socrates_conjunctions.csv"

# Generate realistic SOCRATES conjunction dataset using Python
cat > /tmp/create_socrates_data.py << 'PYEOF'
#!/usr/bin/env python3
import csv
import random
import sys

output_path = sys.argv[1]
random.seed(42)  # Deterministic seed for reproducible verification

records = []
target_sats = ["SAT-AQUA", "SAT-TERRA", "SAT-LANDSAT", "SAT-SENTINEL", "SAT-ICESAT"]
chaser_prefixes = ["FENGYUN 1C DEB", "COSMOS 2251 DEB", "IRIDIUM 33 DEB", "SL-8 DEB", "UNKNOWN"]

# 5 HIGH risk events (Max_Prob >= 1e-4 AND Min_Range_m <= 1000)
for i in range(5):
    records.append([
        random.choice(target_sats),
        f"{random.choice(chaser_prefixes)} {random.randint(10000,99999)}",
        f"2026-03-{random.randint(10,20)}T{random.randint(10,23):02d}:00:00.000Z",
        round(random.uniform(0.1, 0.99), 3),  # Min_Range_km <= 1.0 (<= 1000m)
        round(random.uniform(7.0, 15.0), 3),  # Rel_Velocity_km_s
        f"{random.uniform(1.1, 9.5):.2f}E-04" # Max_Prob >= 1e-4
    ])

# 15 ELEVATED risk events (Max_Prob >= 1e-5 and not HIGH)
# 10 records: Max_Prob between 1e-5 and 9.9e-5, any range
for i in range(10):
    records.append([
        random.choice(target_sats),
        f"{random.choice(chaser_prefixes)} {random.randint(10000,99999)}",
        f"2026-03-{random.randint(10,20)}T{random.randint(10,23):02d}:00:00.000Z",
        round(random.uniform(0.1, 10.0), 3),
        round(random.uniform(7.0, 15.0), 3),
        f"{random.uniform(1.1, 9.5):.2f}E-05"
    ])
# 5 records: Max_Prob >= 1e-4 but Range > 1000m
for i in range(5):
    records.append([
        random.choice(target_sats),
        f"{random.choice(chaser_prefixes)} {random.randint(10000,99999)}",
        f"2026-03-{random.randint(10,20)}T{random.randint(10,23):02d}:00:00.000Z",
        round(random.uniform(1.1, 10.0), 3),
        round(random.uniform(7.0, 15.0), 3),
        f"{random.uniform(1.1, 9.5):.2f}E-04"
    ])

# 180 LOW risk events
for i in range(180):
    records.append([
        random.choice(target_sats),
        f"{random.choice(chaser_prefixes)} {random.randint(10000,99999)}",
        f"2026-03-{random.randint(10,20)}T{random.randint(10,23):02d}:00:00.000Z",
        round(random.uniform(0.1, 20.0), 3),
        round(random.uniform(7.0, 15.0), 3),
        f"{random.uniform(1.1, 9.5):.2f}E-06" # Max_Prob < 1e-5
    ])

random.shuffle(records)

with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["Target_Name", "Chaser_Name", "TCA", "Min_Range_km", "Rel_Velocity_km_s", "Max_Prob"])
    writer.writerows(records)

print(f"Generated {len(records)} conjunction records at {output_path}")
PYEOF

chmod +x /tmp/create_socrates_data.py
su - ga -c "python3 /tmp/create_socrates_data.py '$CSV_PATH'"

# Launch ONLYOFFICE with the CSV file
echo "Launching ONLYOFFICE..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' > /tmp/onlyoffice_task.log 2>&1 &"

# Wait for application window to appear
echo "Waiting for ONLYOFFICE window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Desktop Editors\|ONLYOFFICE"; then
        echo "ONLYOFFICE window detected."
        break
    fi
    sleep 1
done

# Focus and maximize the window
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
sleep 1

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="