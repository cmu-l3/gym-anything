#!/bin/bash
echo "=== Exporting assess_fish_passage_window results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/hec_ras_results/fish_passage_report.json"
PLOT_PATH="/home/ga/Documents/hec_ras_results/velocity_hydrograph.png"
HDF_PATH="$MUNCIE_DIR/Muncie.p04.hdf"

# 1. Check if files exist and were created during task
REPORT_EXISTS="false"
REPORT_CREATED="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED="true"
    fi
fi

PLOT_EXISTS="false"
PLOT_CREATED="false"
if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    MTIME=$(stat -c %Y "$PLOT_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PLOT_CREATED="true"
    fi
fi

# 2. Generate Ground Truth (Run python script inside container to query HDF directly)
# This ensures we verify against the ACTUAL simulation run by the agent
echo "Generating ground truth from HDF file..."

# Create temp python script
cat > /tmp/calc_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import sys
import os

hdf_path = sys.argv[1]
output_path = sys.argv[2]
threshold = 3.5

if not os.path.exists(hdf_path):
    result = {"error": "HDF file not found"}
    with open(output_path, 'w') as f:
        json.dump(result, f)
    sys.exit(0)

try:
    with h5py.File(hdf_path, 'r') as f:
        # Paths based on standard HEC-RAS HDF5 structure (Plan files)
        # Note: Paths can vary slightly by version, trying common ones
        
        # 1. Get River Stations
        # Usually in Geometry/Cross Sections/River Stations
        # or /Geometry/Cross Sections/Attributes (depending on version/file type)
        # For p04.hdf (Plan result), it often links to geometry or copies it.
        
        # Try standard result location
        base_path = '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series'
        
        # Get Velocity Data
        # Shape is usually (Time, CrossSection)
        vel_ds = f[f'{base_path}/Cross Sections/Velocity Channel']
        velocity_data = vel_ds[:] # Load into memory
        
        # Get River Stations (strings)
        # Often encoded as bytes
        try:
            geom_path = '/Geometry/Cross Sections/River Stations'
            rs_ds = f[geom_path]
            river_stations = [x.decode('utf-8').strip() for x in rs_ds[:]]
        except KeyError:
             # Fallback: Try looking in attributes or other paths
             # For this task, we assume standard structure. If fails, agent fails (or sim didn't run right).
             result = {"error": "Could not locate River Stations in HDF"}
             with open(output_path, 'w') as f:
                json.dump(result, f)
             sys.exit(0)

        # 2. Find Critical XS (Max Velocity)
        # Max over time for each XS
        max_vel_per_xs = np.max(velocity_data, axis=0)
        
        # Global max index
        critical_idx = np.argmax(max_vel_per_xs)
        critical_rs = river_stations[critical_idx]
        max_vel = float(max_vel_per_xs[critical_idx])
        
        # 3. Calculate Duration below threshold
        # Get time series for critical XS
        crit_ts = velocity_data[:, critical_idx]
        
        # Count steps < threshold
        # We need time interval. 
        # Check Time array
        time_ds = f[f'{base_path}/Time']
        time_array = time_ds[:]
        
        # Calculate duration based on time step
        # Assuming constant time step for simplicity, or sum intervals
        # HEC-RAS time is usually strings or hours from start. 
        # Easier: The Time Date Stamp usually implies the interval.
        # But commonly Unsteady output is fixed interval.
        # Let's check array length and attributes.
        
        # Standard Muncie example is often 1 hour output or 15 min.
        # Let's derive it from the time array string or first/last.
        # Actually, simpler: count fraction of steps * total duration?
        # No, Unsteady output has a 'Time Step' attribute or we calculate mean dt.
        
        # Robust method:
        # If time_array is in hours (float), calc dt.
        # If time_array is strings, we need to parse or check simulation params.
        # For Muncie p04, Time is usually stored as "Hours since start" in the underlying dataset 'Time' (float)
        # or it is a dataset of strings.
        
        # Let's check 'Time' dataset type. 
        # Usually /Results/.../Time is a float array of hours.
        if time_array.dtype.kind in 'fi': # Float or Int
            times = time_array
            # Calc dt (mode of differences to handle small jitter)
            dts = np.diff(times)
            dt = np.median(dts)
        else:
            # Fallback default (1 hour)
            dt = 1.0 
            
        passable_steps = np.sum(crit_ts < threshold)
        passable_hours = float(passable_steps * dt)
        
        result = {
            "ground_truth_available": True,
            "critical_river_station": critical_rs,
            "max_channel_velocity_fps": max_vel,
            "passable_duration_hours": passable_hours,
            "dt_used": float(dt)
        }
        
        with open(output_path, 'w') as f:
            json.dump(result, f)

except Exception as e:
    result = {"error": str(e), "ground_truth_available": False}
    with open(output_path, 'w') as f:
        json.dump(result, f)
EOF

python3 /tmp/calc_ground_truth.py "$HDF_PATH" /tmp/ground_truth.json

# 3. Prepare Agent Results
cp "$REPORT_PATH" /tmp/agent_report.json 2>/dev/null || echo "{}" > /tmp/agent_report.json

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create Master Result JSON
python3 -c "
import json
import os

try:
    with open('/tmp/agent_report.json', 'r') as f:
        agent = json.load(f)
except:
    agent = {}

try:
    with open('/tmp/ground_truth.json', 'r') as f:
        gt = json.load(f)
except:
    gt = {}

combined = {
    'report_exists': '$REPORT_EXISTS' == 'true',
    'report_created_during_task': '$REPORT_CREATED' == 'true',
    'plot_exists': '$PLOT_EXISTS' == 'true',
    'plot_created_during_task': '$PLOT_CREATED' == 'true',
    'agent_data': agent,
    'ground_truth': gt,
    'hdf_exists': os.path.exists('$HDF_PATH')
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(combined, f, indent=2)
"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="