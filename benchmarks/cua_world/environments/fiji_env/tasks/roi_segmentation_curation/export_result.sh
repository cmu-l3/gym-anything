#!/bin/bash
echo "=== Exporting ROI Curation Results ==="

TASK_DIR="/home/ga/Fiji_Data/curation"
OUTPUT_ZIP="$TASK_DIR/curated_ground_truth.zip"
JSON_OUT="/tmp/task_result.json"

# Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

FILE_EXISTS="false"
FILE_CREATED_DURING="false"
ROI_COUNT=0
JSON_DATA="{}"

if [ -f "$OUTPUT_ZIP" ]; then
    FILE_EXISTS="true"
    MTIME=$(stat -c %Y "$OUTPUT_ZIP")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING="true"
    fi

    # --- Analyze the Agent's ROIs using Fiji Headless ---
    # We can't easily parse .roi files in bash/python without specific libs.
    # So we use Fiji to open the zip and dump measurements to CSV.
    
    ANALYSIS_MACRO="/tmp/analyze_result.ijm"
    RESULT_CSV="/tmp/agent_measurements.csv"
    
    cat > "$ANALYSIS_MACRO" << EOF
    open("$TASK_DIR/training_image.tif");
    run("Set Scale...", "distance=0 known=0 pixel=1 unit=pixel");
    
    // Clear any existing ROIs
    if (roiManager("count") > 0) {
        roiManager("Deselect");
        roiManager("Delete");
    }
    
    // Open agent's zip
    res = roiManager("Open", "$OUTPUT_ZIP");
    
    count = roiManager("count");
    print("ROI_COUNT:" + count);
    
    if (count > 0) {
        run("Set Measurements...", "centroid center area redirect=None decimal=2");
        roiManager("Deselect");
        roiManager("Measure");
        saveAs("Results", "$RESULT_CSV");
    }
    run("Quit");
EOF
    
    echo "Running analysis macro..."
    /usr/local/bin/fiji --headless --console -macro "$ANALYSIS_MACRO" > /tmp/analysis_log.txt 2>&1
    
    # Extract ROI count from log if possible
    ROI_COUNT=$(grep "ROI_COUNT:" /tmp/analysis_log.txt | cut -d':' -f2 | tr -d '\r')
    if [ -z "$ROI_COUNT" ]; then ROI_COUNT=0; fi
    
    # Convert CSV to JSON structure using Python
    if [ -f "$RESULT_CSV" ]; then
        JSON_DATA=$(python3 -c "
import csv, json
data = []
try:
    with open('$RESULT_CSV', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Clean keys/values
            clean_row = {k.strip(): float(v) for k, v in row.items() if k and v}
            data.append(clean_row)
except Exception as e:
    pass
print(json.dumps(data))
")
    fi
fi

# Load Ground Truth Info for context
GT_INFO="{}"
if [ -f "/tmp/roi_ground_truth_info.json" ]; then
    GT_INFO=$(cat /tmp/roi_ground_truth_info.json)
fi

# Assemble Final JSON
cat > "$JSON_OUT" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING,
    "roi_count": $ROI_COUNT,
    "measurements": $JSON_DATA,
    "ground_truth_info": $GT_INFO,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Permissions
chmod 666 "$JSON_OUT"

echo "Result exported to $JSON_OUT"