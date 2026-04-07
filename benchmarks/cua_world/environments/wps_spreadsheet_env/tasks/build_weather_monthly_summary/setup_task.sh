#!/bin/bash
set -e
echo "=== Setting up build_weather_monthly_summary task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Download NOAA data
NOAA_URL="https://www.ncei.noaa.gov/data/global-historical-climatology-network-daily/access/USW00094728.csv"
RAW_CSV="/tmp/USW00094728.csv"

echo "Downloading NOAA GHCN-Daily data..."
wget -q --timeout=30 -O "$RAW_CSV" "$NOAA_URL" || curl -m 30 -sL -o "$RAW_CSV" "$NOAA_URL" || true

if [ ! -s "$RAW_CSV" ]; then
    echo "Warning: Download failed. Using inline fallback data to ensure task can run."
    # Create a minimalistic fallback CSV with headers so pandas doesn't crash
    cat > "$RAW_CSV" << 'EOF'
STATION,DATE,TMAX,TMIN,PRCP,SNWD,AWND
USW00094728,2023-01-01,150,50,0,0,30
USW00094728,2023-01-02,160,60,10,0,40
USW00094728,2023-02-01,100,0,50,10,50
EOF
fi

# Create the XLSX from the raw NOAA CSV using Python
python3 << 'PYEOF'
import pandas as pd
from openpyxl import Workbook
import json

df = pd.read_csv("/tmp/USW00094728.csv", low_memory=False)

# Parse dates (Support fallback cases cleanly)
if 'DATE' not in df.columns:
    df['DATE'] = pd.to_datetime(['2023-01-01'])
else:
    df['DATE'] = pd.to_datetime(df['DATE'])

df_2023 = df[(df['DATE'].dt.year == 2023)].copy()

if df_2023.empty:
    df_2023 = df.head(365).copy()

result = pd.DataFrame()
result['Date'] = df_2023['DATE'].dt.strftime('%Y-%m-%d')
result['Month'] = df_2023['DATE'].dt.month

# Convert to appropriate units (Fahrenheit, Inches, mph)
if 'TMAX' in df_2023.columns:
    result['Max Temperature (°F)'] = (df_2023['TMAX'].astype(float) / 10 * 9/5 + 32).round(1)
else:
    result['Max Temperature (°F)'] = 60.0

if 'TMIN' in df_2023.columns:
    result['Min Temperature (°F)'] = (df_2023['TMIN'].astype(float) / 10 * 9/5 + 32).round(1)
else:
    result['Min Temperature (°F)'] = 40.0

if 'PRCP' in df_2023.columns:
    result['Precipitation (in)'] = (df_2023['PRCP'].astype(float) / 10 / 25.4).round(2)
else:
    result['Precipitation (in)'] = 0.0

if 'SNWD' in df_2023.columns:
    result['Snow Depth (in)'] = (df_2023['SNWD'].fillna(0).astype(float) / 25.4).round(1)
else:
    result['Snow Depth (in)'] = 0.0

if 'AWND' in df_2023.columns:
    result['Avg Wind Speed (mph)'] = (df_2023['AWND'].fillna(0).astype(float) / 10 * 2.237).round(1)
else:
    result['Avg Wind Speed (mph)'] = 0.0

# Cleanup missing data records
result = result.dropna(subset=['Max Temperature (°F)', 'Min Temperature (°F)', 'Precipitation (in)'])
result = result.reset_index(drop=True)

# Generate Workbook
wb = Workbook()
ws = wb.active
ws.title = "Daily Data"

headers = ['Date', 'Month', 'Max Temperature (°F)', 'Min Temperature (°F)', 
           'Precipitation (in)', 'Snow Depth (in)', 'Avg Wind Speed (mph)']
for col_idx, header in enumerate(headers, 1):
    ws.cell(row=1, column=col_idx, value=header)

for row_idx, row in result.iterrows():
    ws.cell(row=row_idx + 2, column=1, value=row['Date'])
    ws.cell(row=row_idx + 2, column=2, value=int(row['Month']))
    ws.cell(row=row_idx + 2, column=3, value=float(row['Max Temperature (°F)']))
    ws.cell(row=row_idx + 2, column=4, value=float(row['Min Temperature (°F)']))
    ws.cell(row=row_idx + 2, column=5, value=float(row['Precipitation (in)']))
    ws.cell(row=row_idx + 2, column=6, value=float(row['Snow Depth (in)']))
    ws.cell(row=row_idx + 2, column=7, value=float(row['Avg Wind Speed (mph)']))

# Auto-adjust layout
for col in ws.columns:
    max_length = max(len(str(cell.value or '')) for cell in col)
    ws.column_dimensions[col[0].column_letter].width = max_length + 2

wb.save("/home/ga/Documents/central_park_weather_2023.xlsx")

# Precompute ground truth expectations for robust verification
gt = {'monthly': {}, 'annual': {}}
data = result.to_dict('records')

for m in range(1, 13):
    month_data = [d for d in data if int(d['Month']) == m]
    if month_data:
        avg_high = sum(d['Max Temperature (°F)'] for d in month_data) / len(month_data)
        avg_low = sum(d['Min Temperature (°F)'] for d in month_data) / len(month_data)
        total_prcp = sum(d['Precipitation (in)'] for d in month_data)
        max_temp = max(d['Max Temperature (°F)'] for d in month_data)
        min_temp = min(d['Min Temperature (°F)'] for d in month_data)
        prcp_days = sum(1 for d in month_data if d['Precipitation (in)'] > 0)
        
        gt['monthly'][str(m)] = {
            'avg_high': round(avg_high, 1),
            'avg_low': round(avg_low, 1),
            'total_prcp': round(total_prcp, 2),
            'max_temp': round(max_temp, 1),
            'min_temp': round(min_temp, 1),
            'prcp_days': prcp_days
        }

if data:
    all_tmax = [d['Max Temperature (°F)'] for d in data]
    all_tmin = [d['Min Temperature (°F)'] for d in data]
    all_prcp = [d['Precipitation (in)'] for d in data]

    gt['annual'] = {
        'avg_high': round(sum(all_tmax) / len(all_tmax), 1),
        'avg_low': round(sum(all_tmin) / len(all_tmin), 1),
        'total_prcp': round(sum(all_prcp), 2),
        'total_prcp_days': sum(1 for p in all_prcp if p > 0)
    }

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=2)

PYEOF

chown ga:ga /home/ga/Documents/central_park_weather_2023.xlsx

# Ensure clean state
pkill -x et 2>/dev/null || true
pkill -f "/office6/et" 2>/dev/null || true
sleep 2

# Launch WPS Spreadsheet
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; et /home/ga/Documents/central_park_weather_2023.xlsx &"

# Wait for WPS window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "central_park_weather\|WPS Spreadsheets\|\.xlsx"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for reference
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="