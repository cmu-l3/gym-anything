#!/bin/bash
echo "=== Exporting Tumor Heterogeneity Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Get sample ID
SAMPLE_ID=$(cat /tmp/brats_sample_id 2>/dev/null || echo "BraTS2021_00000")
BRATS_DIR="/home/ga/Documents/SlicerData/BraTS"

# Define expected output paths
STATS_CSV="$BRATS_DIR/tumor_statistics.csv"
REPORT_JSON="$BRATS_DIR/heterogeneity_report.json"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true
sleep 1

# Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
echo "Task timing: start=$TASK_START, end=$TASK_END"

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi
echo "Slicer running: $SLICER_RUNNING"

# ================================================================
# Check CSV file
# ================================================================
CSV_EXISTS="false"
CSV_HAS_DATA="false"
CSV_CREATED_AFTER_START="false"
CSV_PATH=""

# Check multiple possible locations for CSV
POSSIBLE_CSV_PATHS=(
    "$STATS_CSV"
    "$BRATS_DIR/statistics.csv"
    "$BRATS_DIR/segment_statistics.csv"
    "/home/ga/Documents/tumor_statistics.csv"
    "/home/ga/tumor_statistics.csv"
)

for path in "${POSSIBLE_CSV_PATHS[@]}"; do
    if [ -f "$path" ]; then
        CSV_EXISTS="true"
        CSV_PATH="$path"
        echo "Found CSV at: $path"
        
        # Check if it has data (more than just header)
        LINE_COUNT=$(wc -l < "$path" 2>/dev/null || echo "0")
        if [ "$LINE_COUNT" -gt 1 ]; then
            CSV_HAS_DATA="true"
        fi
        
        # Check timestamp
        CSV_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
            CSV_CREATED_AFTER_START="true"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$STATS_CSV" ]; then
            cp "$path" "$STATS_CSV" 2>/dev/null || true
        fi
        break
    fi
done

echo "CSV: exists=$CSV_EXISTS, has_data=$CSV_HAS_DATA, created_after_start=$CSV_CREATED_AFTER_START"

# ================================================================
# Check JSON report
# ================================================================
REPORT_EXISTS="false"
REPORT_VALID="false"
REPORT_CREATED_AFTER_START="false"
REPORT_PATH=""

# Initialize reported values
REPORTED_MEAN=""
REPORTED_SD=""
REPORTED_CV=""
REPORTED_CLASS=""
REPORTED_MIN=""
REPORTED_MAX=""

# Check multiple possible locations for report
POSSIBLE_REPORT_PATHS=(
    "$REPORT_JSON"
    "$BRATS_DIR/report.json"
    "$BRATS_DIR/tumor_report.json"
    "/home/ga/Documents/heterogeneity_report.json"
    "/home/ga/heterogeneity_report.json"
)

for path in "${POSSIBLE_REPORT_PATHS[@]}"; do
    if [ -f "$path" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$path"
        echo "Found report at: $path"
        
        # Check timestamp
        REPORT_MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
            REPORT_CREATED_AFTER_START="true"
        fi
        
        # Try to parse JSON and extract values
        if python3 -c "import json; json.load(open('$path'))" 2>/dev/null; then
            REPORT_VALID="true"
            
            REPORTED_MEAN=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('mean_intensity', d.get('mean', '')))" 2>/dev/null || echo "")
            REPORTED_SD=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('std_intensity', d.get('std', d.get('standard_deviation', ''))))" 2>/dev/null || echo "")
            REPORTED_CV=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('coefficient_of_variation_percent', d.get('cv', d.get('CV', ''))))" 2>/dev/null || echo "")
            REPORTED_CLASS=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('heterogeneity_class', d.get('classification', '')))" 2>/dev/null || echo "")
            REPORTED_MIN=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('min_intensity', d.get('min', '')))" 2>/dev/null || echo "")
            REPORTED_MAX=$(python3 -c "import json; d=json.load(open('$path')); print(d.get('max_intensity', d.get('max', '')))" 2>/dev/null || echo "")
            
            echo "Parsed report values:"
            echo "  Mean: $REPORTED_MEAN"
            echo "  SD: $REPORTED_SD"
            echo "  CV: $REPORTED_CV"
            echo "  Class: $REPORTED_CLASS"
            echo "  Min: $REPORTED_MIN"
            echo "  Max: $REPORTED_MAX"
        fi
        
        # Copy to expected location if different
        if [ "$path" != "$REPORT_JSON" ]; then
            cp "$path" "$REPORT_JSON" 2>/dev/null || true
        fi
        break
    fi
done

echo "Report: exists=$REPORT_EXISTS, valid=$REPORT_VALID, created_after_start=$REPORT_CREATED_AFTER_START"

# ================================================================
# Copy files for verification
# ================================================================
echo "Preparing files for verification..."

# Copy ground truth
if [ -f /tmp/heterogeneity_gt.json ]; then
    chmod 644 /tmp/heterogeneity_gt.json 2>/dev/null || true
fi

# Copy agent report if exists
if [ -f "$REPORT_JSON" ]; then
    cp "$REPORT_JSON" /tmp/agent_heterogeneity_report.json 2>/dev/null || true
    chmod 644 /tmp/agent_heterogeneity_report.json 2>/dev/null || true
fi

# Copy CSV if exists
if [ -f "$STATS_CSV" ]; then
    cp "$STATS_CSV" /tmp/agent_statistics.csv 2>/dev/null || true
    chmod 644 /tmp/agent_statistics.csv 2>/dev/null || true
fi

# ================================================================
# Create result JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sample_id": "$SAMPLE_ID",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "slicer_running": $SLICER_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_has_data": $CSV_HAS_DATA,
    "csv_created_after_start": $CSV_CREATED_AFTER_START,
    "csv_path": "$CSV_PATH",
    "report_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_VALID,
    "report_created_after_start": $REPORT_CREATED_AFTER_START,
    "report_path": "$REPORT_PATH",
    "reported_mean": "$REPORTED_MEAN",
    "reported_sd": "$REPORTED_SD",
    "reported_cv": "$REPORTED_CV",
    "reported_class": "$REPORTED_CLASS",
    "reported_min": "$REPORTED_MIN",
    "reported_max": "$REPORTED_MAX",
    "screenshot_final": "/tmp/task_final_state.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="