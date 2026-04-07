#!/bin/bash
echo "=== Setting up audit_campaign_contributions task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

DATA_FILE="/home/ga/Documents/fec_contributions.csv"
rm -f "$DATA_FILE" 2>/dev/null || true
rm -f "/home/ga/Documents/campaign_audit.xlsx" 2>/dev/null || true

# Generate realistic FEC contribution data using Python
python3 << 'PYEOF'
import csv
import random

states = ['CA', 'NY', 'TX', 'FL', 'IL', 'PA', 'OH', 'GA', 'NC', 'MI', 'VA', 'WA', 'MA', 'CO']
employers = ['SELF-EMPLOYED', 'RETIRED', 'NOT EMPLOYED', 'GOOGLE', 'MICROSOFT', 'ACME CORP', 'STATE UNIVERSITY']
occupations = ['CEO', 'RETIRED', 'ENGINEER', 'TEACHER', 'CONSULTANT', 'ATTORNEY', 'PHYSICIAN', 'NOT EMPLOYED']

with open('/home/ga/Documents/fec_contributions.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    # A=0, B=1, C=2, D=3(STATE), E=4, F=5, G=6, H=7(TRANSACTION_DT), I=8(TRANSACTION_AMT)
    writer.writerow([
        'CMTE_ID', 'NAME', 'CITY', 'STATE', 'ZIP_CODE', 
        'EMPLOYER', 'OCCUPATION', 'TRANSACTION_DT', 'TRANSACTION_AMT'
    ])
    
    for i in range(150):
        state = random.choice(states)
        month = random.choice(['01', '02', '03', '04', '05', '06', '07', '08', '09', '10', '11', '12'])
        day = f"{random.randint(1, 28):02d}"
        year = random.choice(['2023', '2024'])
        dt = f"{month}{day}{year}"
        
        # Determine amount - create realistic distribution with some intentional >$3300 limits
        r = random.random()
        if r < 0.85:
            amt = round(random.uniform(5, 500), 2)
        elif r < 0.95:
            amt = round(random.uniform(500, 3300), 2)
        else:
            # Over the federal limit (needs to be flagged)
            amt = round(random.uniform(3301, 6000), 2)
            
        writer.writerow([
            f'C00{random.randint(100000, 999999)}', 
            f'DONOR_{i}', 
            'ANYTOWN', 
            state, 
            f'{random.randint(10000, 99999)}', 
            random.choice(employers), 
            random.choice(occupations), 
            dt, 
            amt
        ])

print("Successfully generated fec_contributions.csv")
PYEOF

# Fix permissions
chown ga:ga "$DATA_FILE" 2>/dev/null || true

# Kill any existing instances of WPS
pkill -x et 2>/dev/null || true
sleep 1

# Launch WPS Spreadsheet with the generated CSV
echo "Starting WPS Spreadsheet..."
su - ga -c "export DISPLAY=:1; et '$DATA_FILE' &"

# Wait for window to appear
for i in {1..20}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "WPS Spreadsheet"; then
        echo "WPS Spreadsheet window detected"
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "WPS Spreadsheet" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "WPS Spreadsheet" 2>/dev/null || true

# Wait for rendering to settle
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="