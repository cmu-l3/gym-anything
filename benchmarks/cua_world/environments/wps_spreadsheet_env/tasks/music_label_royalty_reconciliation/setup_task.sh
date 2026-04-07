#!/bin/bash
echo "=== Setting up Music Label Royalty Reconciliation task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

FILE_PATH="/home/ga/Documents/royalty_statement_Q3.xlsx"
rm -f "$FILE_PATH" 2>/dev/null || true

# Generate realistic royalty data
python3 << 'PYEOF'
import random
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

wb = Workbook()
ws_stream = wb.active
ws_stream.title = "Streaming_Data"
ws_contracts = wb.create_sheet("Contracts")

# 1. Setup Contracts
artists = [
    {"name": "The Midnight", "rate": 0.50, "advance": 5000},
    {"name": "Gunship", "rate": 0.25, "advance": 1000},
    {"name": "Timecop1983", "rate": 0.15, "advance": 0},
    {"name": "FM-84", "rate": 0.30, "advance": 15000},
    {"name": "Kavinsky", "rate": 0.20, "advance": 2000}
]

ws_contracts.append(["Artist", "Royalty_Rate", "Unrecouped_Advance"])
for a in artists:
    ws_contracts.append([a["name"], a["rate"], a["advance"]])

# 2. Setup Streaming Data
ws_stream.append(["ISRC", "Track_Name", "Artist", "Platform", "Streams", "Total_Revenue"])
platforms = ["Spotify", "Apple Music", "Tidal", "Amazon Music"]

random.seed(42) # Deterministic data for predictable verification
for i in range(1, 76):
    artist = random.choice(artists)["name"]
    streams = random.randint(50000, 2000000)
    rev = round(streams * 0.004, 2)
    ws_stream.append([f"USRC{i:04d}", f"Track {i}", artist, random.choice(platforms), streams, rev])

# 3. Apply Basic Formatting
header_font = Font(bold=True)
fill = PatternFill(start_color='DDDDDD', end_color='DDDDDD', fill_type='solid')

for ws in [ws_stream, ws_contracts]:
    for cell in ws[1]:
        cell.font = header_font
        cell.fill = fill

for row in ws_contracts.iter_rows(min_row=2, max_row=ws_contracts.max_row, min_col=2, max_col=2):
    for cell in row:
        cell.number_format = '0%'

for row in ws_contracts.iter_rows(min_row=2, max_row=ws_contracts.max_row, min_col=3, max_col=3):
    for cell in row:
        cell.number_format = '$#,##0.00'

for row in ws_stream.iter_rows(min_row=2, max_row=ws_stream.max_row, min_col=6, max_col=6):
    for cell in row:
        cell.number_format = '$#,##0.00'

wb.save("/home/ga/Documents/royalty_statement_Q3.xlsx")
print("Data file generated successfully.")
PYEOF

chown ga:ga "$FILE_PATH"

# Ensure WPS is running and open the file
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$FILE_PATH' > /dev/null 2>&1 &"
    sleep 8
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "WPS Spreadsheets" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="