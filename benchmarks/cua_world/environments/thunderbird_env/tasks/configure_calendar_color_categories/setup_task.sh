#!/bin/bash
set -euo pipefail

echo "=== Setting up Configure Calendar Color Categories task ==="

source /workspace/scripts/task_utils.sh || echo "Warning: task_utils.sh not found"

# 1. Create the busy_schedule.ics file using Python to handle dates dynamically
mkdir -p /home/ga/Documents

cat << 'EOF' > /tmp/generate_ics.py
import datetime
import os

now = datetime.datetime.now(datetime.timezone.utc)
dates = [now + datetime.timedelta(days=i) for i in range(-1, 3)]

events = [
    # Dummy events
    ("Weekly Standup", dates[0].replace(hour=9, minute=0), dates[0].replace(hour=9, minute=30)),
    ("Lunch with Team", dates[0].replace(hour=12, minute=0), dates[0].replace(hour=13, minute=0)),
    ("Budget Review Prep", dates[0].replace(hour=14, minute=0), dates[0].replace(hour=15, minute=0)),
    ("Design Sync", dates[1].replace(hour=10, minute=0), dates[1].replace(hour=11, minute=0)),
    ("1:1 with Sarah", dates[1].replace(hour=15, minute=0), dates[1].replace(hour=15, minute=30)),
    ("Project Alpha Kickoff", dates[2].replace(hour=11, minute=0), dates[2].replace(hour=12, minute=0)),
    ("Vendor Call", dates[2].replace(hour=16, minute=0), dates[2].replace(hour=16, minute=30)),
    
    # Target events
    ("Q3 Roadmap Review", dates[1].replace(hour=13, minute=0), dates[1].replace(hour=14, minute=0)),
    ("Acme Corp Pitch", dates[2].replace(hour=14, minute=0), dates[2].replace(hour=15, minute=30)),
    ("Dentist Appointment", dates[1].replace(hour=8, minute=0), dates[1].replace(hour=9, minute=0)),
]

ics_content = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Mozilla.org/NONSGML Mozilla Calendar V1.1//EN"
]

for i, (title, start, end) in enumerate(events):
    start_str = start.strftime("%Y%m%dT%H%M%SZ")
    end_str = end.strftime("%Y%m%dT%H%M%SZ")
    ics_content.extend([
        "BEGIN:VEVENT",
        f"UID:event{i}@example.com",
        f"SUMMARY:{title}",
        f"DTSTART:{start_str}",
        f"DTEND:{end_str}",
        "END:VEVENT"
    ])

ics_content.append("END:VCALENDAR")

with open("/home/ga/Documents/busy_schedule.ics", "w") as f:
    f.write("\n".join(ics_content))

os.chown("/home/ga/Documents/busy_schedule.ics", 1000, 1000) # Assuming ga is uid/gid 1000
EOF

python3 /tmp/generate_ics.py
echo "Created busy_schedule.ics"

# 2. Start Thunderbird
echo "Starting Thunderbird..."
if ! pgrep -f "thunderbird" > /dev/null; then
    su - ga -c "DISPLAY=:1 thunderbird -profile /home/ga/.thunderbird/default-release &" 2>/dev/null
    sleep 8
fi

# 3. Wait for window and maximize
WID=$(su - ga -c "DISPLAY=:1 xdotool search --name 'Thunderbird' 2>/dev/null" | head -1)
if [ -n "$WID" ]; then
    su - ga -c "DISPLAY=:1 wmctrl -i -r '$WID' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    su - ga -c "DISPLAY=:1 wmctrl -i -a '$WID'" 2>/dev/null || true
fi

# 4. Save start time and take initial screenshot
date +%s > /tmp/task_start_time.txt
sleep 2
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup complete ==="