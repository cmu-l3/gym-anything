#!/bin/bash
set -e
echo "=== Setting up Hospital Daily Census Task ==="

# 1. Create directory structure
mkdir -p /home/ga/Desktop/PowerBITasks
mkdir -p /var/lib/powerbi

# 2. Generate Synthetic Data and Ground Truth
# We use Python to generate realistic hospital data (Poisson arrivals, LogNormal LOS)
# and simultaneously calculate the 'ground truth' daily census to verify against.

cat > /tmp/generate_data.py << 'EOF'
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random

# Setup
np.random.seed(42)  # Deterministic generation
start_date = datetime(2023, 1, 1)
end_date = datetime(2024, 12, 31)
days = (end_date - start_date).days
departments = ['General', 'Surgery', 'ICU', 'Oncology']
types = ['Inpatient', 'Outpatient', 'Emergency']

data = []
enc_id = 10001
pat_id = 50001

# Generate Encounters
current_date = start_date
while current_date <= end_date:
    # Daily arrivals (Poisson)
    num_arrivals = np.random.poisson(lam=15)
    
    for _ in range(num_arrivals):
        p_type = np.random.choice(types, p=[0.6, 0.3, 0.1])
        dept = np.random.choice(departments)
        
        # LOS (Length of Stay)
        if p_type == 'Inpatient':
            # LogNormal for inpatient LOS
            los = max(1, int(np.random.lognormal(mean=1.5, sigma=0.8)))
        else:
            los = 0 # Same day discharge
            
        admit = current_date
        discharge = admit + timedelta(days=los)
        
        data.append({
            'Encounter_ID': enc_id,
            'Patient_ID': pat_id,
            'Admit_Date': admit.strftime('%Y-%m-%d'),
            'Discharge_Date': discharge.strftime('%Y-%m-%d'),
            'Department': dept,
            'Patient_Type': p_type
        })
        enc_id += 1
        pat_id += 1 # Simplified new patient every time
        
    current_date += timedelta(days=1)

df = pd.DataFrame(data)

# Save Source File for Agent
df.to_csv('/home/ga/Desktop/PowerBITasks/hospital_encounters.csv', index=False)
print(f"Generated {len(df)} encounters.")

# --- Calculate Ground Truth (Hidden from Agent) ---
# Filter Inpatient
df_inp = df[df['Patient_Type'] == 'Inpatient'].copy()
df_inp['Admit_Date'] = pd.to_datetime(df_inp['Admit_Date'])
df_inp['Discharge_Date'] = pd.to_datetime(df_inp['Discharge_Date'])

# Create daily census
date_range = pd.date_range(start=start_date, end=end_date)
census_data = []

for d in date_range:
    # Logic: Active if Admit <= d <= Discharge
    count = df_inp[
        (df_inp['Admit_Date'] <= d) & 
        (df_inp['Discharge_Date'] >= d)
    ].shape[0]
    census_data.append({'Date': d.strftime('%Y-%m-%d'), 'Census': count})

gt_df = pd.DataFrame(census_data)
gt_df.to_csv('/var/lib/powerbi/hospital_ground_truth.csv', index=False)
print("Ground truth calculated.")
EOF

echo "Generating dataset..."
python3 /tmp/generate_data.py

# 3. Ensure Power BI is running and ready
date +%s > /tmp/task_start_time.txt

if ! pgrep -f "PBIDesktop" > /dev/null; then
    echo "Starting Power BI Desktop..."
    # Note: Adjust the command below to match your environment's PBI executable path
    # Using the standard path from the environment description context
    su - ga -c "DISPLAY=:1 /c/Program\ Files/Microsoft\ Power\ BI\ Desktop/bin/PBIDesktop.exe &"
    
    # Wait loop
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Power BI"; then
            echo "Power BI detected."
            break
        fi
        sleep 1
    done
fi

# Maximize Window
sleep 5
DISPLAY=:1 wmctrl -r "Power BI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Power BI" 2>/dev/null || true

# Close any startup dialogs (Esc x 3 is a safe pattern)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="