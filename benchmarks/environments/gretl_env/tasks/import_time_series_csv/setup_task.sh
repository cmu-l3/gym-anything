#!/bin/bash
set -euo pipefail

echo "=== Setting up import_time_series_csv task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is empty
mkdir -p /home/ga/Documents/gretl_output
rm -f /home/ga/Documents/gretl_output/*
chown ga:ga /home/ga/Documents/gretl_output

# =====================================================================
# Prepare the Raw CSV Data
# We want to force the agent to define the time series structure,
# so we create a CSV with just values (gdp, inf) and NO date column.
# =====================================================================
echo "Generating raw CSV data..."

CSV_PATH="/home/ga/Documents/raw_macro.csv"

# We try to use the real usa.gdt data if available to keep values realistic
USA_GDT="/opt/gretl_data/poe5/usa.gdt"

if [ -f "$USA_GDT" ]; then
    # Use gretlcli to dump data to CSV
    # script: open data, store to csv
    echo "open \"$USA_GDT\"" > /tmp/export.inp
    echo "store \"/tmp/temp_export.csv\" --csv" >> /tmp/export.inp
    
    # Run as ga user
    su - ga -c "gretlcli -b /tmp/export.inp" >/dev/null 2>&1 || true
    
    if [ -f "/tmp/temp_export.csv" ]; then
        # Python script to strip the date/obs column and keep only gdp, inf
        python3 -c "
import pandas as pd
try:
    df = pd.read_csv('/tmp/temp_export.csv')
    # Filter for gdp and inf columns (case insensitive)
    cols = [c for c in df.columns if c.lower().strip() in ['gdp', 'inf', 'realgdp', 'inflation']]
    if cols:
        df[cols].to_csv('$CSV_PATH', index=False)
        print(f'Created CSV with columns: {cols}')
    else:
        raise Exception('Columns not found')
except Exception as e:
    print(f'Python CSV processing failed: {e}')
    exit(1)
" || rm -f "$CSV_PATH" # Delete if python failed so we hit fallback
    fi
fi

# Fallback if generation failed
if [ ! -f "$CSV_PATH" ]; then
    echo "Using fallback data generation..."
    cat > "$CSV_PATH" << 'CSV_EOF'
gdp,inf
3637.5,3.7742
3704.8,4.5241
3759.5,4.0722
3794.7,3.3168
3865.1,3.473
3904.3,3.3361
3973.5,3.1365
4007.4,3.7061
4065.1,1.9429
4086.5,1.7454
4115.1,1.8687
4136.1,2.9461
CSV_EOF
fi

chown ga:ga "$CSV_PATH"
chmod 644 "$CSV_PATH"

# =====================================================================
# Launch Gretl (Empty)
# =====================================================================
echo "Launching Gretl..."
kill_gretl

# Launch without a dataset
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    setsid gretl >/home/ga/gretl_launch.log 2>&1 &"

# Wait for window
wait_for_gretl 30 || true

# Maximize
maximize_gretl

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Raw CSV created at: $CSV_PATH"