#!/bin/bash
echo "=== Exporting compute_inundated_area results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
PROJECT_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
HDF_FILE="$PROJECT_DIR/Muncie.p04.hdf"

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Generate Ground Truth (Hidden from agent)
# We calculate the true value using a trusted script right now
echo "Generating ground truth data..."
cat > /tmp/calc_ground_truth.py << 'EOF'
import h5py
import numpy as np
import sys
import os

try:
    hdf_path = sys.argv[1]
    
    if not os.path.exists(hdf_path):
        print(f"ERROR: HDF file not found at {hdf_path}")
        sys.exit(1)

    with h5py.File(hdf_path, 'r') as f:
        # 1. Get Geometry Data (River Stations and Reach Lengths)
        # Structure varies, looking for typical RAS paths
        # Usually: /Geometry/Cross Sections/Attributes or similar
        # For simplicity in this robust script, we look for standard paths
        
        # Try finding Cross Section Attributes
        geom_path = '/Geometry/Cross Sections/Attributes'
        if geom_path not in f:
            # Fallback for some versions
            geom_path = '/Geometry/Cross Sections/Attributes'
        
        # Extract Downstream Reach Lengths (Column 0 is usually LOB, 1 is Channel, 2 is ROB)
        # We need Channel Lengths (index 1)
        reach_lengths_table = f[geom_path][:]
        # Assuming typical structure: [LOB, Channel, ROB] or similar. 
        # Actually in HEC-RAS HDF, "Downstream Reach Lengths" is often a dataset.
        
        # Let's try to find the "Downstream Reach Lengths" dataset directly if it exists,
        # otherwise infer from attributes.
        # In RAS 6.x: /Geometry/Cross Sections/Attributes is a compound type or array.
        # Let's assume column 3 is Channel Reach Length (index 2) or column 2 (index 1).
        # Standard: LOB(0), Channel(1), ROB(2).
        channel_reach_lengths = reach_lengths_table[:, 1] # Index 1 is Main Channel
        
        # 2. Get Results (Top Width)
        # Path: /Results/Unsteady/Output/Output Blocks/Base Output/Unsteady/Cross Sections/Variables
        # We need to find the "Top Width" variable index.
        # Variable names are stored in /Results/Unsteady/Output/Output Blocks/Base Output/Unsteady/Cross Sections/Variable Names
        
        var_names_path = '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady/Cross Sections/Variable Names'
        var_names = [n.decode('utf-8') for n in f[var_names_path][:]]
        
        if 'Top Width' not in var_names:
            print("ERROR: Top Width variable not found")
            sys.exit(1)
            
        tw_idx = var_names.index('Top Width')
        
        # Get Data: [Time, CrossSection, Variable]
        # We need MAX over time for each CrossSection
        data_path = '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady/Cross Sections/Variables'
        # Shape is typically (Time, XS, Var)
        all_data = f[data_path][:]
        
        # Extract Top Widths
        top_widths_time = all_data[:, :, tw_idx]
        
        # Compute Max Top Width for each XS
        max_top_widths = np.max(top_widths_time, axis=0)
        
        # 3. Compute Area (Trapezoidal)
        # Area = 0.5 * (W_i + W_{i-1}) * L_channel_i
        # Note: Reach length at i is distance to i-1 (downstream)
        
        total_sq_ft = 0.0
        # Iterate from upstream to downstream (indices usually correspond to river station order in file)
        # But we need to be careful about matching. 
        # HDF storage order usually matches geometry order.
        
        # Check alignment:
        num_xs = len(max_top_widths)
        if len(channel_reach_lengths) != num_xs:
             # Sometimes geometry has more/less if interpolated. 
             # For this env, assume 1-to-1 map for base cross sections.
             pass

        for i in range(num_xs - 1): # Last XS usually has 0 reach length or connects to nothing
            w1 = max_top_widths[i]
            w2 = max_top_widths[i+1] # Next downstream
            l = channel_reach_lengths[i]
            
            # Simple trapz
            segment_area = 0.5 * (w1 + w2) * l
            total_sq_ft += segment_area
            
        total_acres = total_sq_ft / 43560.0
        print(f"GROUND_TRUTH_ACRES:{total_acres:.4f}")

except Exception as e:
    print(f"ERROR: {str(e)}")
    sys.exit(1)
EOF

# Run the ground truth script
GROUND_TRUTH_OUTPUT=$(python3 /tmp/calc_ground_truth.py "$HDF_FILE")
GROUND_TRUTH_ACRES=$(echo "$GROUND_TRUTH_OUTPUT" | grep "GROUND_TRUTH_ACRES" | cut -d':' -f2)

if [ -z "$GROUND_TRUTH_ACRES" ]; then
    echo "WARNING: Failed to calculate ground truth. Script output:"
    echo "$GROUND_TRUTH_OUTPUT"
    GROUND_TRUTH_ACRES="0.0"
fi
echo "Calculated Ground Truth: $GROUND_TRUTH_ACRES acres"

# 3. Check Agent Outputs
REPORT_FILE="$RESULTS_DIR/inundated_area_report.txt"
CSV_FILE="$RESULTS_DIR/reach_data.csv"
PLOT_FILE="$RESULTS_DIR/top_width_profile.png"
SCRIPT_FILE=$(find "$RESULTS_DIR" -name "*.py" | head -1)

# Report
REPORT_EXISTS="false"
REPORTED_VALUE="0.0"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Extract number (acres)
    REPORTED_VALUE=$(grep -oE "[0-9]+\.?[0-9]*" "$REPORT_FILE" | head -1 || echo "0.0")
fi

# CSV
CSV_EXISTS="false"
CSV_LINES="0"
if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_LINES=$(wc -l < "$CSV_FILE" || echo "0")
fi

# Plot
PLOT_EXISTS="false"
if [ -f "$PLOT_FILE" ]; then
    PLOT_EXISTS="true"
fi

# Script
SCRIPT_EXISTS="false"
if [ -n "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
fi

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "ground_truth_acres": $GROUND_TRUTH_ACRES,
    "agent_report": {
        "exists": $REPORT_EXISTS,
        "path": "$REPORT_FILE",
        "value": $REPORTED_VALUE
    },
    "agent_csv": {
        "exists": $CSV_EXISTS,
        "lines": $CSV_LINES
    },
    "agent_plot": {
        "exists": $PLOT_EXISTS
    },
    "agent_script": {
        "exists": $SCRIPT_EXISTS
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to shared location
rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="