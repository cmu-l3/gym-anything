#!/bin/bash
set -euo pipefail

echo "=== Setting up build_production_failure_analysis task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

DATA_DIR="/home/ga/Documents"
TEMP_DIR="/tmp/prod_data_prep"
mkdir -p "$DATA_DIR" "$TEMP_DIR"

# Clean up any previous runs
rm -f "$DATA_DIR/production_data.xlsx"
rm -f "$DATA_DIR/production_analysis.xlsx"

# 1. Download real AI4I 2020 Predictive Maintenance Dataset
echo "Downloading AI4I 2020 dataset..."
wget -q -O "$TEMP_DIR/ai4i2020.zip" "https://archive.ics.uci.edu/static/public/601/ai4i+2020+predictive+maintenance+dataset.zip" || {
    echo "Failed to download dataset. Using fallback mock data generator..."
    # Fallback if UCI is down (creates a basic structure so task doesn't completely fail)
    python3 -c "
import pandas as pd, numpy as np
np.random.seed(42)
n = 10000
df = pd.DataFrame({
    'UDI': range(1, n+1),
    'Product ID': ['M'+str(i) for i in range(10000, 10000+n)],
    'Type': np.random.choice(['L', 'M', 'H'], n, p=[0.6, 0.3, 0.1]),
    'Air temperature [K]': np.random.normal(300, 2, n),
    'Process temperature [K]': np.random.normal(310, 1.5, n),
    'Rotational speed [rpm]': np.random.normal(1500, 50, n),
    'Torque [Nm]': np.random.normal(40, 5, n),
    'Tool wear [min]': np.random.uniform(0, 250, n),
    'Machine failure': np.random.choice([0, 1], n, p=[0.96, 0.04])
})
for f in ['TWF', 'HDF', 'PWF', 'OSF', 'RNF']:
    df[f] = (df['Machine failure'] == 1) & (np.random.rand(n) > 0.8)
    df[f] = df[f].astype(int)
df.to_csv('$TEMP_DIR/ai4i2020.csv', index=False)
    "
}

# Extract if downloaded successfully
if [ -f "$TEMP_DIR/ai4i2020.zip" ]; then
    unzip -q -o "$TEMP_DIR/ai4i2020.zip" -d "$TEMP_DIR/"
fi

# 2. Convert CSV to XLSX and compute Ground Truth
echo "Converting data and computing ground truth..."
python3 << 'PYEOF'
import pandas as pd
import json
from openpyxl import Workbook
from openpyxl.utils.dataframe import dataframe_to_rows
import os

csv_path = "/tmp/prod_data_prep/ai4i2020.csv"
if not os.path.exists(csv_path):
    print(f"Error: {csv_path} not found.")
    exit(1)

df = pd.read_csv(csv_path)
df.columns = df.columns.str.strip()

# Save ground truth
gt = {}

# Summary Stats
for t in ['H', 'M', 'L']:
    subset = df[df['Type'] == t]
    gt[f'count_{t}'] = int(len(subset))
    gt[f'failed_{t}'] = int(subset['Machine failure'].sum())
    
gt['count_Total'] = int(len(df))
gt['failed_Total'] = int(df['Machine failure'].sum())

# Types Stats
for t in ['H', 'M', 'L']:
    subset = df[df['Type'] == t]
    for ft in ['TWF', 'HDF', 'PWF', 'OSF', 'RNF']:
        gt[f'{t}_{ft}'] = int(subset[ft].sum())

# Process Stats
params = [
    'Air temperature [K]', 
    'Process temperature [K]',
    'Rotational speed [rpm]', 
    'Torque [Nm]', 
    'Tool wear [min]'
]

for p in params:
    for fail_val, group in [(0, 'No Failure'), (1, 'Failure')]:
        subset = df[df['Machine failure'] == fail_val][p]
        key_prefix = f"{p}_{group}"
        gt[f'{key_prefix}_avg'] = float(subset.mean()) if len(subset) > 0 else 0.0
        gt[f'{key_prefix}_min'] = float(subset.min()) if len(subset) > 0 else 0.0
        gt[f'{key_prefix}_max'] = float(subset.max()) if len(subset) > 0 else 0.0

os.makedirs("/var/lib/app", exist_ok=True)
with open("/var/lib/app/ground_truth.json", "w") as f:
    json.dump(gt, f, indent=2)

# Create Workbook
wb = Workbook()
ws = wb.active
ws.title = "RawData"

for r_idx, row in enumerate(dataframe_to_rows(df, index=False, header=True), 1):
    for c_idx, value in enumerate(row, 1):
        ws.cell(row=r_idx, column=c_idx, value=value)

for col in ws.columns:
    ws.column_dimensions[col[0].column_letter].width = 15

wb.save("/home/ga/Documents/production_data.xlsx")
print(f"Prepared XLSX with {len(df)} rows.")
PYEOF

chown ga:ga "$DATA_DIR/production_data.xlsx"
chmod 644 "$DATA_DIR/production_data.xlsx"

# 3. Start WPS Spreadsheet
if ! pgrep -f "et " > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et /home/ga/Documents/production_data.xlsx &"
    sleep 8
fi

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize Window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

# Cleanup
rm -rf "$TEMP_DIR"

echo "=== Task setup complete ==="