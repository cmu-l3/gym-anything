#!/bin/bash
set -e
echo "=== Setting up schedule_irregular_training_series task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Calculate dates for "Next Week" to ensure they are in the future and consistent
# We use Python to handle the date math robustly
python3 << 'PYTHON_EOF'
import datetime
import json
import os

# Calculate next Monday
today = datetime.date.today()
days_ahead = 7 - today.weekday()
if days_ahead <= 0: # Target next week if today is Monday
    days_ahead += 7
next_monday = today + datetime.timedelta(days=days_ahead)
next_wednesday = next_monday + datetime.timedelta(days=2)
next_thursday = next_monday + datetime.timedelta(days=3)

# Define schedule details
schedule = [
    {
        "day_str": next_monday.strftime("%A, %B %d, %Y"),
        "start_time": "10:00 AM",
        "end_time": "12:00 PM",
        "iso_date": next_monday.isoformat(),
        "start_hour": 10,
        "duration_hours": 2
    },
    {
        "day_str": next_wednesday.strftime("%A, %B %d, %Y"),
        "start_time": "02:00 PM",
        "end_time": "04:00 PM",
        "iso_date": next_wednesday.isoformat(),
        "start_hour": 14,
        "duration_hours": 2
    },
    {
        "day_str": next_thursday.strftime("%A, %B %d, %Y"),
        "start_time": "09:00 AM",
        "end_time": "11:00 AM",
        "iso_date": next_thursday.isoformat(),
        "start_hour": 9,
        "duration_hours": 2
    }
]

# Write the instructions file for the agent
file_path = "/home/ga/Documents/leadership_schedule.txt"
os.makedirs(os.path.dirname(file_path), exist_ok=True)
with open(file_path, "w") as f:
    f.write("LEADERSHIP 101 - TRAINING SCHEDULE\n")
    f.write("==================================\n\n")
    f.write("Please schedule the following 3 separate sessions in the company calendar.\n")
    f.write("For all sessions, include Alice Johnson and Frank Rivera as attendees.\n")
    f.write("Location: Board Room\n")
    f.write("Description: Core leadership principles for new managers.\n\n")
    
    for i, sess in enumerate(schedule, 1):
        f.write(f"SESSION {i}:\n")
        f.write(f"Date:  {sess['day_str']}\n")
        f.write(f"Time:  {sess['start_time']} - {sess['end_time']}\n\n")

print(f"Created schedule file at {file_path}")

# Save the ground truth for the verifier/export script
# We save the expected UTC datetimes for the database check.
# Assuming Odoo and system are in same timezone or handling UTC correctly.
# Odoo DB usually stores UTC. If the agent enters "10:00 AM" in the UI, 
# and the user timezone is set, Odoo converts. 
# For simplicity in this environment, we assume the agent's UI input matches the stored hour
# roughly or we check the hour component specifically in the verifier.
with open("/tmp/ground_truth_schedule.json", "w") as f:
    json.dump(schedule, f)

PYTHON_EOF

# Ensure directory permissions
chown -R ga:ga /home/ga/Documents

# Launch Firefox to the Calendar
ensure_firefox "http://localhost:8069/web#action=calendar.action_calendar_event"

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="