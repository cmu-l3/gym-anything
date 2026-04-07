#!/bin/bash
set -e
echo "=== Setting up hotel_cancellation_analysis task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

HOTEL_FILE="/home/ga/Documents/resort_hotel_bookings.xlsx"
rm -f "$HOTEL_FILE" 2>/dev/null || true

# We will use Python to download real Hotel Booking data and format it.
# If the network fails, it falls back to a realistic data generator.
echo "Preparing realistic hotel booking dataset..."
python3 << 'PYEOF'
import os
import pandas as pd
import urllib.request
import random
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

file_path = "/home/ga/Documents/resort_hotel_bookings.xlsx"
url = "https://raw.githubusercontent.com/rfordatascience/tidytuesday/master/data/2020/2020-02-11/hotels.csv"

def generate_fallback_data():
    print("Generating realistic fallback data...")
    segments = ["Online TA", "Offline TA/TO", "Direct", "Corporate", "Groups"]
    months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    
    data = []
    for i in range(1, 5001):
        lead_time = int(random.expovariate(1/45))
        is_canceled = 1 if random.random() < 0.27 else 0
        market = random.choices(segments, weights=[0.45, 0.20, 0.15, 0.10, 0.10])[0]
        
        data.append({
            'id': f'RES-{i}',
            'is_canceled': is_canceled,
            'lead_time': lead_time,
            'arrival_date_month': random.choice(months),
            'stays_in_weekend_nights': random.randint(0, 2),
            'stays_in_week_nights': random.randint(1, 5),
            'adults': random.randint(1, 4),
            'market_segment': market,
            'adr': round(random.uniform(50.0, 250.0), 2)
        })
    return pd.DataFrame(data)

try:
    print("Attempting to download real dataset...")
    df = pd.read_csv(url)
    resort = df[df['hotel'] == 'Resort Hotel'].copy()
    
    # Format according to task specification
    resort = resort.reset_index(drop=True)
    resort['id'] = 'RES-' + (resort.index + 1).astype(str)
    
    cols = ['id', 'is_canceled', 'lead_time', 'arrival_date_month', 'stays_in_weekend_nights', 'stays_in_week_nights', 'adults', 'market_segment', 'adr']
    final_df = resort[cols].head(5000)
    print("Successfully downloaded and parsed real data.")
except Exception as e:
    print(f"Download failed ({e}). Using fallback generator.")
    final_df = generate_fallback_data()

# Create Excel with OpenPyXL for formatting
wb = Workbook()
ws = wb.active
ws.title = "Bookings"

# Append Headers
headers = final_df.columns.tolist()
ws.append(headers)

# Append Data
for row in final_df.itertuples(index=False):
    ws.append(list(row))

# Format headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color="D9D9D9", end_color="D9D9D9", fill_type="solid")
for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill

# Adjust width
for col in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I']:
    ws.column_dimensions[col].width = 15
ws.column_dimensions['D'].width = 20
ws.column_dimensions['E'].width = 22
ws.column_dimensions['F'].width = 20
ws.column_dimensions['H'].width = 18

wb.save(file_path)
print(f"Saved to {file_path}")
PYEOF

# Ensure the ga user owns the file
chown ga:ga "$HOTEL_FILE" 2>/dev/null || true

# Start WPS Spreadsheet if not running
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$HOTEL_FILE' &"
    sleep 8
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "resort_hotel_bookings"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "resort_hotel_bookings" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "resort_hotel_bookings" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="