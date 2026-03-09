#!/bin/bash
echo "=== Exporting Froude Number Analysis Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
PROJECT_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
AGENT_CSV="$RESULTS_DIR/froude_analysis.csv"
AGENT_REPORT="$RESULTS_DIR/froude_report.txt"
HDF_FILE="$PROJECT_DIR/Muncie.p04.hdf"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check for agent output files
CSV_EXISTS="false"
REPORT_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ -f "$AGENT_CSV" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$AGENT_CSV")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$AGENT_REPORT" ]; then
    REPORT_EXISTS="true"
    MTIME=$(stat -c %Y "$AGENT_REPORT")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Generate GROUND TRUTH data inside the container
# We do this here because the container has h5py and the HDF file.
# The verifier might not have h5py or the large HDF file.
echo "Generating ground truth data..."

python3 -c "
import h5py
import numpy as np
import json
import os
import sys

try:
    hdf_path = '$HDF_FILE'
    if not os.path.exists(hdf_path):
        print(json.dumps({'error': 'HDF file not found'}))
        sys.exit(0)

    with h5py.File(hdf_path, 'r') as f:
        # Navigate to results (standard HEC-RAS 6.x path)
        # Note: Path might vary slightly depending on plan, usually under 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        base_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        
        if base_path not in f:
             # Fallback search or error
             print(json.dumps({'error': f'Path {base_path} not found in HDF'}))
             sys.exit(0)

        xs_grp = f[base_path]
        
        # Get datasets
        # Shape usually: (Time, XS) or (XS, Time) - HEC-RAS is typically (Time, XS) for these
        flow = xs_grp['Flow'][:]
        vel = xs_grp['Velocity Total'][:]
        area = xs_grp['Flow Area'][:]
        top_width = xs_grp['Top Width'][:]
        
        # Get XS names if available
        # They are often attributes or in a separate geometry path. 
        # For simplicity in ground truth, we'll use indices, or try to find names.
        # Geometry path: /Geometry/Cross Sections/Attributes
        xs_names = []
        try:
            geom_path = 'Geometry/Cross Sections/Attributes'
            if geom_path in f:
                names_data = f[geom_path][:]
                # HEC-RAS names are often compound types, we usually want 'River Station'
                # Attempt to decode byte strings
                xs_names = [row[0].decode('utf-8') if isinstance(row[0], bytes) else str(row[0]) for row in names_data]
        except:
            xs_names = [str(i) for i in range(flow.shape[1])]
            
        if len(xs_names) != flow.shape[1]:
             xs_names = [str(i) for i in range(flow.shape[1])]

        # 1. Identify Peak Flow Timestep
        # Sum flow across all XS for each timestep
        total_flow_per_step = np.sum(flow, axis=1)
        peak_idx = int(np.argmax(total_flow_per_step))
        
        # 2. Extract data at peak step
        v_peak = vel[peak_idx, :]
        area_peak = area[peak_idx, :]
        width_peak = top_width[peak_idx, :]
        
        # 3. Compute D and Fr
        # Handle divide by zero for D
        d_peak = np.zeros_like(area_peak)
        mask_w = width_peak > 0.001
        d_peak[mask_w] = area_peak[mask_w] / width_peak[mask_w]
        
        # Handle divide by zero for Fr
        g = 32.174
        fr_peak = np.zeros_like(v_peak)
        mask_d = d_peak > 0.001
        fr_peak[mask_d] = v_peak[mask_d] / np.sqrt(g * d_peak[mask_d])
        
        # 4. Classify
        sub = np.sum(fr_peak < 1.0)
        super_c = np.sum(fr_peak > 1.0) # Floating point comparison note: strict > 1.0
        
        # Prepare JSON output
        truth = {
            'peak_timestep_index': peak_idx,
            'total_cross_sections': len(xs_names),
            'subcritical_count': int(sub),
            'supercritical_count': int(super_c),
            'max_froude': float(np.max(fr_peak)),
            'min_froude': float(np.min(fr_peak)),
            'mean_froude': float(np.mean(fr_peak)),
            'cross_sections': []
        }
        
        for i in range(len(xs_names)):
            truth['cross_sections'].append({
                'name': xs_names[i],
                'velocity': float(v_peak[i]),
                'depth': float(d_peak[i]),
                'froude': float(fr_peak[i])
            })
            
        print(json.dumps(truth))

except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/ground_truth.json

# 4. Copy files to temp location for export
cp "$AGENT_CSV" /tmp/agent_froude.csv 2>/dev/null || true
cp "$AGENT_REPORT" /tmp/agent_report.txt 2>/dev/null || true

# 5. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Ensure permissions for copied files
chmod 666 /tmp/agent_froude.csv 2>/dev/null || true
chmod 666 /tmp/agent_report.txt 2>/dev/null || true
chmod 666 /tmp/ground_truth.json 2>/dev/null || true

echo "=== Export complete ==="