#!/bin/bash
echo "=== Setting up calculate_baseball_sabermetrics task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

STATS_FILE="/home/ga/Documents/batting_stats.xlsx"
rm -f "$STATS_FILE" 2>/dev/null || true
mkdir -p /home/ga/Documents/

# Create realistic baseball statistics spreadsheet using Python
python3 << 'PYEOF'
import random
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()
ws = wb.active
ws.title = 'Raw_Data'

headers = ['PlayerID', 'Name', 'Team', 'G', 'AB', 'R', 'H', '2B', '3B', 'HR', 'RBI', 'BB', 'SO', 'HBP', 'SF']
ws.append(headers)

# Generate 500 rows of realistic MLB player data
teams = ['NYY', 'LAD', 'BOS', 'HOU', 'ATL', 'PHI', 'TOR', 'SEA', 'BAL', 'TEX']
first_names = ['John', 'Mike', 'David', 'Shohei', 'Aaron', 'Mookie', 'Freddie', 'Bryce', 'Corey', 'Julio', 'Juan', 'Jose']
last_names = ['Smith', 'Trout', 'Judge', 'Ohtani', 'Betts', 'Freeman', 'Harper', 'Seager', 'Rodriguez', 'Soto', 'Ramirez']

random.seed(42) # Reproducible data

for i in range(1, 501):
    player_id = 1000 + i
    name = f"{random.choice(first_names)} {random.choice(last_names)}"
    team = random.choice(teams)
    
    # Randomize plate appearances to ensure a mix of >=300 and <300
    pa_type = random.random()
    if pa_type < 0.1:
        pa = random.randint(0, 20)      # Cup of coffee / Pitcher
    elif pa_type < 0.4:
        pa = random.randint(50, 299)    # Bench / Platoon
    else:
        pa = random.randint(300, 700)   # Everyday starter
        
    if pa < 5:
        ab = pa
        bb = hbp = sf = 0
    else:
        bb = int(pa * random.uniform(0.04, 0.16))
        hbp = int(pa * random.uniform(0.00, 0.03))
        sf = int(pa * random.uniform(0.00, 0.04))
        ab = pa - bb - hbp - sf
        
    avg = random.uniform(0.180, 0.330)
    h = int(ab * avg)
    
    hr = int(h * random.uniform(0.02, 0.30))
    d2 = int(h * random.uniform(0.15, 0.28))
    d3 = int(h * random.uniform(0.00, 0.06))
    
    # Ensure H >= 2B + 3B + HR
    while d2 + d3 + hr > h:
        if d3 > 0: d3 -= 1
        elif d2 > 0: d2 -= 1
        elif hr > 0: hr -= 1
        else: break
        
    r = int(h * 0.45 + hr * 1.1 + bb * 0.2)
    rbi = int(h * 0.45 + hr * 1.6 + sf * 1.0)
    so = int(ab * random.uniform(0.12, 0.35))
    g = int(pa / 4.2) if pa > 0 else 0
    if g > 162: g = 162
    
    ws.append([player_id, name, team, g, ab, r, h, d2, d3, hr, rbi, bb, so, hbp, sf])

# Format header row
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color='1F4E78', end_color='1F4E78', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

# Adjust column widths
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 8

wb.save('/home/ga/Documents/batting_stats.xlsx')
PYEOF

chown ga:ga "$STATS_FILE" 2>/dev/null || true

# Start WPS Spreadsheet
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$STATS_FILE' &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "batting_stats"; then
        echo "WPS Spreadsheet window detected"
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r "batting_stats" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "batting_stats" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="