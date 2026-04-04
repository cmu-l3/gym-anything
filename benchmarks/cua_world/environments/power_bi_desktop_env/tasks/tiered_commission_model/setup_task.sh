#!/bin/bash
set -e
echo "=== Setting up Tiered Commission Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Power BI is running
# Using powershell via su - Docker to interact with the Windows user session
if ! pgrep -f "PBIDesktop" > /dev/null; then
    echo "Starting Power BI Desktop..."
    su - Docker -c "powershell -Command 'Start-Process \"C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe\"'"
    sleep 10
fi

# Ensure window is maximized
DISPLAY=:1 wmctrl -r "Power BI Desktop" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Generate quota_targets.csv based on existing sales_data.csv
# We do this dynamically to ensure the data aligns and creates specific test cases
# (Underperformers, On-Target, Overperformers)
echo "Generating Quota Targets..."

python3 -c "
import pandas as pd
import numpy as np
import os

# Path mappings
# Assuming the script runs in Linux environment where C: is mounted or accessible
# In this specific env, we might need to write to a temp location and move it, 
# or use the windows path if running under WSL/Cygwin.
# Given the environment instructions, we'll write to the Desktop path directly if mapped,
# or use a localized path that maps to C:/Users/Docker/Desktop.

# NOTE: Adjusting path for the likely mount point. 
# If not mapped, we write to a temp file and copy it via powershell.
CSV_PATH = '/home/ga/Desktop/PowerBITasks/sales_data.csv'
TARGET_PATH = '/home/ga/Desktop/PowerBITasks/quota_targets.csv'

# Fallback for Windows path if Linux path doesn't exist (assuming script runs in hybrid)
if not os.path.exists(os.path.dirname(CSV_PATH)):
     # Attempt to use Windows paths assuming python is running in Windows context
     CSV_PATH = 'C:/Users/Docker/Desktop/PowerBITasks/sales_data.csv'
     TARGET_PATH = 'C:/Users/Docker/Desktop/PowerBITasks/quota_targets.csv'

try:
    df = pd.read_csv(CSV_PATH)
    
    # Group by Rep to get actuals
    sales_by_rep = df.groupby('Sales_Rep')['Sales_Amount'].sum().reset_index()
    
    quotas = []
    
    # Shuffle reps to randomize who gets what tier, but keep it deterministic for the seed
    reps = sales_by_rep['Sales_Rep'].tolist()
    np.random.seed(12345) 
    np.random.shuffle(reps)
    
    for i, rep in enumerate(reps):
        actual = sales_by_rep[sales_by_rep['Sales_Rep'] == rep]['Sales_Amount'].values[0]
        
        # Create scenarios:
        # 0: Fail (<80%) -> Set Quota high (Actual / 0.7)
        # 1: Target (80-110%) -> Set Quota near Actual (Actual / 0.95)
        # 2: Accelerator (>110%) -> Set Quota low (Actual / 1.2)
        
        scenario = i % 3
        
        if scenario == 0:
            q = actual / 0.70
        elif scenario == 1:
            q = actual / 0.95
        else:
            q = actual / 1.20
            
        # Round nicely
        q = round(q, -2)
        
        quotas.append({'Sales_Rep': rep, 'Quota': q})
        
    q_df = pd.DataFrame(quotas)
    q_df.to_csv(TARGET_PATH, index=False)
    print(f'Successfully generated {TARGET_PATH}')

except Exception as e:
    print(f'Error generating quotas: {e}')
    # Create dummy if fail
    with open('quota_targets.csv', 'w') as f:
        f.write('Sales_Rep,Quota\nJohn Doe,100000\n')
"

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial state
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="