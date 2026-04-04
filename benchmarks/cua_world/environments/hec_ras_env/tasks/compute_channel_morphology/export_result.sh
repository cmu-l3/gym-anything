#!/bin/bash
echo "=== Exporting compute_channel_morphology result ==="

source /workspace/scripts/task_utils.sh

# 1. Record task end time & capture final screenshot
TASK_END=$(date +%s)
take_screenshot /tmp/task_final.png

# 2. Paths
RESULT_JSON="/home/ga/Documents/hec_ras_results/morphology_metrics.json"
HDF_FILE="$MUNCIE_DIR/Muncie.p04.hdf"

# 3. Check if agent output exists
OUTPUT_EXISTS="false"
OUTPUT_CONTENT="{}"
FILE_CREATED_DURING_TASK="false"

if [ -f "$RESULT_JSON" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$RESULT_JSON")
    
    # Check timestamp
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$RESULT_JSON" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 4. Generate Ground Truth (using Python inside container)
# We calculate the metrics directly from the HDF file to compare against agent
cat > /tmp/gen_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import sys

try:
    with h5py.File(sys.argv[1], 'r') as f:
        # 1. Get Reach Lengths (Channel) for Channel Length
        # Location: /Geometry/Cross Sections/Attributes
        # Columns often: [Station, LeftLen, ChannelLen, RightLen, ...]
        # We need to find the index for Channel Length.
        # Alternatively, assume 'Reach Length' is stored.
        
        # Access Attributes dataset
        attrs_data = f['Geometry/Cross Sections/Attributes'][()]
        # The structure is a structured array. Let's look for 'Reach Length' fields.
        # Often named 'Reach Length' or similar in column headers if strictly table, 
        # but in HDF it's usually a compound dataset.
        
        # Let's inspect dtype names
        names = attrs_data.dtype.names
        # Standard HEC-RAS 1D output usually has 'Reach Length'
        
        if 'Reach Length' in names:
            # It might be a single value or struct? 
            # Actually, usually 'Reach Length' is a column if it's a table, 
            # but standard RAS schema puts lengths in 'Attributes'.
            # Let's check for 'LCh' or 'Channel Length'.
            # If standard RAS HDF:
            # attributes usually has 'Reach Length' as a column.
            # Let's try to sum 'Reach Length' column if it exists.
            pass
        
        # Fallback: calculate from stations? No, reach length is explicit.
        # Let's look at standard Muncie example structure.
        # Assuming field name 'Reach Length' exists and is the channel length.
        
        # For this specific verifier script, we'll try to be robust:
        # Sum of 'Reach Length' (Channel)
        
        # If we can't find exact field easily by name without exploration, 
        # we will extract 'Attributes' and look for the length column.
        # In HEC-RAS 6.x: /Geometry/Cross Sections/Attributes
        # Fields: 'River Station', 'Reach Length', ...
        
        # Let's try to get Channel Length sum.
        # Note: The most downstream XS has 0 length.
        total_channel_len = 0.0
        if 'Reach Length' in names:
             total_channel_len = np.sum(attrs_data['Reach Length'])
        else:
            # Try finding column 2 (0-indexed) if it's a raw array? No, h5py returns structured.
            # Let's dump names for debugging if needed
            pass

        # 2. Get Invert Elevations
        # 'Minimum Channel Elevation' in Attributes?
        up_invert = 0.0
        down_invert = 0.0
        if 'Minimum Channel Elevation' in names:
            up_invert = attrs_data['Minimum Channel Elevation'][-1] # Upstream usually last or first? 
            # RAS stores upstream to downstream? Or river station order?
            # Usually River Station is decreasing downstream.
            # We sort by River Station to be sure.
            
            # Sort data by River Station (descending)
            # River Station is often stored as string.
            sorted_indices = np.argsort([float(x) for x in attrs_data['River Station']])[::-1]
            sorted_data = attrs_data[sorted_indices]
            
            up_invert = sorted_data['Minimum Channel Elevation'][0]
            down_invert = sorted_data['Minimum Channel Elevation'][-1]
            
            # Re-sum length based on sorted order (though sum is invariant)
            total_channel_len = np.sum(sorted_data['Reach Length'])
        
        # 3. Valley Length from Centerlines
        # /Geometry/River Centerlines/Polyline Points
        valley_len = 0.0
        if 'Geometry/River Centerlines' in f:
            centerlines = f['Geometry/River Centerlines']
            # There might be multiple reaches. Muncie is usually one.
            # Sum the Euclidean distance of start-end for each reach?
            # Or just start of first to end of last?
            # Prompt says "straight-line distance between start and end of river centerline".
            
            # Concatenate all points?
            # Let's get the very first point of the first reach and very last of last reach.
            # Assuming one river.
            
            # Attributes to find mapping?
            # Let's just grab the 'Polyline Points' dataset.
            pts = centerlines['Polyline Points'][()]
            # Shape (N, 2).
            # Dist = sqrt((x1-x2)^2 + (y1-y2)^2)
            p_start = pts[0]
            p_end = pts[-1]
            valley_len = np.sqrt(np.sum((p_start - p_end)**2))
        
        # Calculations
        sinuosity = 0.0
        if valley_len > 0:
            sinuosity = total_channel_len / valley_len
            
        slope = 0.0
        if total_channel_len > 0:
            slope = (up_invert - down_invert) / total_channel_len

        result = {
            "channel_length_ft": float(total_channel_len),
            "valley_length_ft": float(valley_len),
            "sinuosity_index": float(sinuosity),
            "upstream_invert_el_ft": float(up_invert),
            "downstream_invert_el_ft": float(down_invert),
            "average_bed_slope": float(slope),
            "debug_attrs": list(names)
        }
        
        print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

# Run ground truth generation
GROUND_TRUTH_JSON=$(python3 /tmp/gen_ground_truth.py "$HDF_FILE")

# 5. Create Final JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "agent_output": $OUTPUT_CONTENT,
    "ground_truth": $GROUND_TRUTH_JSON
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="