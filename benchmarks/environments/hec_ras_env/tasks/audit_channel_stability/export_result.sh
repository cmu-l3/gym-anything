#!/bin/bash
echo "=== Exporting Audit Channel Stability Results ==="

source /workspace/scripts/task_utils.sh

# Directories
PROJECT_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
CSV_PATH="$RESULTS_DIR/velocity_compliance_audit.csv"
PLOT_PATH="$RESULTS_DIR/velocity_profile_audit.png"

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Outputs
CSV_EXISTS="false"
PLOT_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
PLOT_CREATED_DURING_TASK="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    PLOT_MTIME=$(stat -c %Y "$PLOT_PATH" 2>/dev/null || echo "0")
    if [ "$PLOT_MTIME" -gt "$TASK_START" ]; then
        PLOT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Generate Ground Truth (Hidden from Agent)
# We run a python script to inspect the HDF file and generate the true max velocities
# This runs inside the container environment where h5py is installed
echo "Generating ground truth..."

cat > /tmp/generate_ground_truth.py << 'PYEOF'
import h5py
import numpy as np
import json
import os
import sys

project_dir = "/home/ga/Documents/hec_ras_projects/Muncie"
# Try standard result filenames
hdf_candidates = [
    os.path.join(project_dir, "Muncie.p04.hdf"),
    os.path.join(project_dir, "Muncie.p04.tmp.hdf")
]

hdf_path = None
for p in hdf_candidates:
    if os.path.exists(p):
        hdf_path = p
        break

output = {
    "simulation_run": False,
    "cross_sections": []
}

if hdf_path:
    try:
        with h5py.File(hdf_path, 'r') as f:
            output["simulation_run"] = True
            
            # Paths to data (standard HEC-RAS 6.x paths)
            # Geometry stations
            # Try 1D geometry path first
            if 'Geometry/Cross Sections/River Stations' in f:
                stations_dset = f['Geometry/Cross Sections/River Stations']
                stations = [s.decode('utf-8').strip() for s in stations_dset[:]]
            else:
                # Fallback or error
                stations = []

            # Velocity data: Time x Station
            # Path: Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Velocity Channel
            vel_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Velocity Channel'
            
            if vel_path in f:
                vel_data = f[vel_path][:] # Shape: (Time, Station)
                # Compute max over time for each station
                max_vels = np.max(vel_data, axis=0)
                
                for i, station in enumerate(stations):
                    if i < len(max_vels):
                        output["cross_sections"].append({
                            "station": station,
                            "max_velocity": float(max_vels[i])
                        })
    except Exception as e:
        output["error"] = str(e)

print(json.dumps(output))
PYEOF

# Run the ground truth generation
GROUND_TRUTH_JSON=$(python3 /tmp/generate_ground_truth.py 2>/dev/null || echo '{"simulation_run": false, "error": "Script failed"}')
echo "$GROUND_TRUTH_JSON" > /tmp/ground_truth.json

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "plot_exists": $PLOT_EXISTS,
    "plot_created_during_task": $PLOT_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move files for extraction
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
chmod 666 /tmp/ground_truth.json 2>/dev/null || true
if [ "$CSV_EXISTS" = "true" ]; then
    cp "$CSV_PATH" /tmp/agent_output.csv
    chmod 666 /tmp/agent_output.csv
fi
if [ "$PLOT_EXISTS" = "true" ]; then
    cp "$PLOT_PATH" /tmp/agent_plot.png
    chmod 666 /tmp/agent_plot.png
fi

echo "=== Export complete ==="