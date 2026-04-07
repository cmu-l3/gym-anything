#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up ED Throughput & LOS Analysis Task ==="

# Record task start timestamp for anti-gaming verification
TASK_START=$(date +%s)
echo $TASK_START > /tmp/task_start_time.txt

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/ed_visit_logs_q3.csv"

# Generate realistic clinical ED dataset
cat > /tmp/create_ed_data.py << 'PYEOF'
#!/usr/bin/env python3
"""
Generate a realistic Emergency Department visit log dataset using established
clinical probability distributions, similar to patterns found in Synthea/MIMIC.
"""
import csv
import sys
import random
from datetime import datetime, timedelta

output_path = sys.argv[1]
random.seed(42)  # Deterministic seed

records = []
start_date = datetime(2023, 7, 1, 0, 0)

# Realistic ED Acuity distribution (ESI 1-5)
esi_choices = [1]*1 + [2]*20 + [3]*45 + [4]*25 + [5]*9
dispo_choices = ['Discharged']*70 + ['Admitted']*20 + ['Transferred']*5 + ['AMA']*1

for i in range(1500):
    # Random arrival time over Q3 (92 days)
    arrival = start_date + timedelta(minutes=random.randint(0, 92*24*60))
    esi = random.choice(esi_choices)
    
    # Triage typically 2-15 mins after arrival
    triage = arrival + timedelta(minutes=random.randint(2, 15))
    
    # MD seen delay based on acuity
    if esi == 1: md_delay = random.randint(0, 5)
    elif esi == 2: md_delay = random.randint(5, 30)
    elif esi == 3: md_delay = random.randint(20, 90)
    elif esi == 4: md_delay = random.randint(30, 120)
    else: md_delay = random.randint(45, 180)
    
    md_seen = arrival + timedelta(minutes=md_delay)
    
    # LOS (Length of Stay) based on Acuity
    if esi == 1: los_mins = random.randint(180, 500)
    elif esi == 2: los_mins = random.randint(120, 400)
    elif esi == 3: los_mins = random.randint(100, 400)
    elif esi == 4: los_mins = random.randint(60, 240)
    else: los_mins = random.randint(30, 180)
    
    departure = arrival + timedelta(minutes=los_mins)
    
    # Left Without Being Seen (LWBS) logic - typical ~4% overall rate
    is_lwbs = random.random() < 0.04
    
    if is_lwbs:
        md_seen_str = ""
        dispo = "LWBS"
        departure = arrival + timedelta(minutes=random.randint(15, 120))
    else:
        md_seen_str = md_seen.strftime('%Y-%m-%d %H:%M')
        dispo = random.choice(dispo_choices)
        # ESI 1 almost always admitted or transferred
        if esi == 1 and dispo == 'Discharged':
            dispo = 'Admitted'
            
    records.append({
        'Visit_ID': f"ED-2023-{8001+i}",
        'Arrival_Time': arrival.strftime('%Y-%m-%d %H:%M'),
        'Triage_Time': triage.strftime('%Y-%m-%d %H:%M'),
        'MD_Seen_Time': md_seen_str,
        'Departure_Time': departure.strftime('%Y-%m-%d %H:%M'),
        'Acuity_ESI': esi,
        'Disposition': dispo
    })

# Sort by arrival time
records.sort(key=lambda x: x['Arrival_Time'])

# Write to CSV
with open(output_path, 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=records[0].keys())
    writer.writeheader()
    writer.writerows(records)

print(f"Generated {len(records)} realistic ED records at {output_path}")
PYEOF

chmod +x /tmp/create_ed_data.py
sudo -u ga python3 /tmp/create_ed_data.py "$CSV_PATH"

# Start ONLYOFFICE with the CSV file
echo "Launching ONLYOFFICE..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' > /tmp/onlyoffice_task.log 2>&1 &"

# Wait for window and maximize
if wait_for_window "ONLYOFFICE\|Desktop Editors" 30; then
    WID=$(get_onlyoffice_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Take initial state screenshot
sleep 2
echo "Capturing initial state..."
su - ga -c "DISPLAY=:1 import -window root /tmp/task_initial.png" || true

echo "=== Task setup complete ==="