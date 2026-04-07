#!/bin/bash
echo "=== Setting up call_center_performance_analysis task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

FILE_PATH="/home/ga/Documents/call_center_data.xlsx"
rm -f "$FILE_PATH" 2>/dev/null || true

# Generate realistic call center data
python3 << 'PYEOF'
import openpyxl
from openpyxl.styles import Font
import random
from datetime import datetime, timedelta

wb = openpyxl.Workbook()
ws_logs = wb.active
ws_logs.title = 'Call_Logs'

headers = ['Call_ID', 'Agent_ID', 'Call_Date', 'Duration_Seconds', 'Resolved', 'CSAT_Score']
ws_logs.append(headers)
for cell in ws_logs[1]:
    cell.font = Font(bold=True)

ws_roster = wb.create_sheet('Agent_Roster')
roster_headers = ['Agent_ID', 'Agent_Name', 'Hire_Date']
ws_roster.append(roster_headers)
for cell in ws_roster[1]:
    cell.font = Font(bold=True)

first_names = ["James", "Mary", "John", "Patricia", "Robert", "Jennifer", "Michael", "Linda", 
               "William", "Elizabeth", "David", "Barbara", "Richard", "Susan", "Joseph", 
               "Jessica", "Thomas", "Sarah", "Charles", "Karen"]

agents = []
for i in range(20):
    agent_id = f"AGT-{101+i}"
    agent_name = f"{first_names[i]}"
    agents.append(agent_id)
    ws_roster.append([agent_id, agent_name, '2023-01-15'])

random.seed(42)
start_date = datetime(2024, 5, 1)

for i in range(1, 5201):
    call_id = f"CALL-{10000+i}"
    agent_id = random.choice(agents)
    call_date = start_date + timedelta(days=random.randint(0, 30), minutes=random.randint(0, 1440))
    duration = max(60, int(random.gauss(450, 150)))
    resolved = 'Y' if random.random() < 0.78 else 'N'
    csat = random.choices([1, 2, 3, 4, 5, ''], weights=[0.05, 0.05, 0.1, 0.3, 0.4, 0.1])[0]
    ws_logs.append([call_id, agent_id, call_date.strftime('%Y-%m-%d %H:%M'), duration, resolved, csat])

wb.save('/home/ga/Documents/call_center_data.xlsx')
PYEOF

chown ga:ga "$FILE_PATH" 2>/dev/null || true

# Open WPS Spreadsheet
su - ga -c "DISPLAY=:1 et '$FILE_PATH' > /dev/null 2>&1 &"
sleep 5

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "call_center"; then
        DISPLAY=:1 wmctrl -i -r $(DISPLAY=:1 wmctrl -l | grep -i "call_center" | awk '{print $1}' | head -1) -b add,maximized_vert,maximized_horz
        DISPLAY=:1 wmctrl -i -a $(DISPLAY=:1 wmctrl -l | grep -i "call_center" | awk '{print $1}' | head -1)
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="