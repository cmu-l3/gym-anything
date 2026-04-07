#!/bin/bash
echo "=== Setting up airbnb_investment_analysis task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any existing output from previous runs
rm -f /home/ga/Documents/airbnb_analysis.xlsx 2>/dev/null || true
rm -f /home/ga/Documents/asheville_listings.csv 2>/dev/null || true

# Generate realistic raw Airbnb CSV data
python3 << 'PYEOF'
import csv
import random
import os

os.makedirs('/home/ga/Documents', exist_ok=True)
random.seed(42)
neighborhoods = ['Downtown', 'West Asheville', 'Biltmore Village', 'Montford', 'Kenilworth', 'River Arts District', 'East End', 'Haw Creek']

with open('/home/ga/Documents/asheville_listings.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'name', 'neighbourhood', 'price', 'reviews_per_month'])
    for i in range(1, 501):
        nh = random.choice(neighborhoods)
        price_val = random.uniform(50, 1500)
        price_str = f"${price_val:,.2f}"
        
        # Introduce blank cells to test formula robustness
        if random.random() < 0.15:
            revs = ""
        else:
            revs = round(random.uniform(0.1, 8.0), 2)
            
        writer.writerow([i, f"Listing {i}", nh, price_str, revs])
PYEOF

# Ensure proper ownership
chown ga:ga /home/ga/Documents/asheville_listings.csv

# Launch WPS Spreadsheet with the CSV
if ! pgrep -x "et" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 et /home/ga/Documents/asheville_listings.csv > /dev/null 2>&1 &"
    sleep 6
fi

# Focus and Maximize the Window
DISPLAY=:1 wmctrl -r "asheville_listings.csv" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "WPS Spreadsheets" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "asheville_listings" 2>/dev/null || true

# Allow UI to stabilize and take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="