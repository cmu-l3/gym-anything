#!/bin/bash
echo "=== Exporting Calculate Segment Statistics Result ==="

source /workspace/scripts/task_utils.sh

EXPORTS_DIR="/home/ga/Documents/SlicerData/Exports"
OUTPUT_CSV="$EXPORTS_DIR/tumor_statistics.csv"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/segstats_final.png ga
sleep 1

# ============================================================
# Check if Slicer is running
# ============================================================
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# ============================================================
# Search for CSV output files
# ============================================================
echo "Searching for CSV output files..."

CSV_EXISTS="false"
CSV_SIZE_BYTES="0"
CSV_MTIME="0"
FILE_CREATED_DURING_TASK="false"
CSV_PATH=""

# Search locations (in priority order)
SEARCH_PATHS=(
    "$OUTPUT_CSV"
    "$EXPORTS_DIR/SegmentStatistics.csv"
    "$EXPORTS_DIR/Segment*.csv"
    "/home/ga/Documents/*.csv"
    "/home/ga/*.csv"
    "/home/ga/Desktop/*.csv"
)

for pattern in "${SEARCH_PATHS[@]}"; do
    found=$(ls -t $pattern 2>/dev/null | head -1)
    if [ -n "$found" ] && [ -f "$found" ]; then
        CSV_PATH="$found"
        CSV_EXISTS="true"
        CSV_SIZE_BYTES=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
        CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
        
        # Check if created during task
        if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
        
        echo "Found CSV: $CSV_PATH (size: $CSV_SIZE_BYTES bytes, mtime: $CSV_MTIME)"
        break
    fi
done

# Also check for table files (.tsv, .txt) that Slicer might export
if [ "$CSV_EXISTS" = "false" ]; then
    for pattern in "$EXPORTS_DIR/*.tsv" "$EXPORTS_DIR/*.txt" "/home/ga/*.tsv"; do
        found=$(ls -t $pattern 2>/dev/null | head -1)
        if [ -n "$found" ] && [ -f "$found" ]; then
            # Check if it looks like segment statistics
            if grep -qi "segment\|volume\|necrotic\|edema\|enhancing" "$found" 2>/dev/null; then
                CSV_PATH="$found"
                CSV_EXISTS="true"
                CSV_SIZE_BYTES=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
                CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
                if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
                    FILE_CREATED_DURING_TASK="true"
                fi
                echo "Found table file: $CSV_PATH"
                break
            fi
        fi
    done
fi

# ============================================================
# Parse CSV content if found
# ============================================================
CSV_VALID="false"
NUM_ROWS="0"
NUM_COLS="0"
HAS_SEGMENT_COL="false"
HAS_VOLUME_COL="false"
HAS_INTENSITY_COL="false"
SEGMENTS_FOUND=""
EXTRACTED_DATA=""

if [ "$CSV_EXISTS" = "true" ] && [ -f "$CSV_PATH" ]; then
    echo "Parsing CSV content..."
    
    EXTRACTED_DATA=$(python3 << PYEOF
import csv
import json
import sys

csv_path = "$CSV_PATH"
result = {
    "valid": False,
    "num_rows": 0,
    "num_cols": 0,
    "has_segment_col": False,
    "has_volume_col": False,
    "has_intensity_col": False,
    "columns": [],
    "segments_found": [],
    "segment_data": {}
}

try:
    # Try different delimiters
    with open(csv_path, 'r') as f:
        sample = f.read(2048)
        f.seek(0)
        
        # Detect delimiter
        if '\t' in sample:
            delimiter = '\t'
        elif ';' in sample:
            delimiter = ';'
        else:
            delimiter = ','
        
        reader = csv.DictReader(f, delimiter=delimiter)
        rows = list(reader)
        
        if rows:
            result["valid"] = True
            result["num_rows"] = len(rows)
            result["columns"] = list(rows[0].keys()) if rows else []
            result["num_cols"] = len(result["columns"])
            
            # Check for required columns (case-insensitive)
            cols_lower = [c.lower() for c in result["columns"]]
            
            # Segment column
            for col in cols_lower:
                if "segment" in col or "name" in col or "label" in col:
                    result["has_segment_col"] = True
                    break
            
            # Volume column
            for col in cols_lower:
                if "volume" in col or "voxel" in col or "count" in col:
                    result["has_volume_col"] = True
                    break
            
            # Intensity column
            for col in cols_lower:
                if any(x in col for x in ["mean", "median", "min", "max", "std", "intensity", "average"]):
                    result["has_intensity_col"] = True
                    break
            
            # Extract segment data
            segment_col = None
            for col in result["columns"]:
                if any(x in col.lower() for x in ["segment", "name", "label"]):
                    segment_col = col
                    break
            
            if segment_col:
                for row in rows:
                    seg_name = row.get(segment_col, "").strip()
                    if seg_name:
                        result["segments_found"].append(seg_name)
                        
                        # Extract numeric values
                        seg_data = {}
                        for col, val in row.items():
                            try:
                                # Try to convert to float
                                num_val = float(val.replace(',', '.'))
                                seg_data[col] = num_val
                            except (ValueError, AttributeError):
                                seg_data[col] = val
                        result["segment_data"][seg_name] = seg_data

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)
    
    if [ -n "$EXTRACTED_DATA" ]; then
        CSV_VALID=$(echo "$EXTRACTED_DATA" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('valid', False)).lower())")
        NUM_ROWS=$(echo "$EXTRACTED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('num_rows', 0))")
        NUM_COLS=$(echo "$EXTRACTED_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('num_cols', 0))")
        HAS_SEGMENT_COL=$(echo "$EXTRACTED_DATA" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('has_segment_col', False)).lower())")
        HAS_VOLUME_COL=$(echo "$EXTRACTED_DATA" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('has_volume_col', False)).lower())")
        HAS_INTENSITY_COL=$(echo "$EXTRACTED_DATA" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('has_intensity_col', False)).lower())")
        SEGMENTS_FOUND=$(echo "$EXTRACTED_DATA" | python3 -c "import json,sys; print(','.join(json.load(sys.stdin).get('segments_found', [])))")
        
        echo "CSV valid: $CSV_VALID"
        echo "Rows: $NUM_ROWS, Cols: $NUM_COLS"
        echo "Has segment column: $HAS_SEGMENT_COL"
        echo "Has volume column: $HAS_VOLUME_COL"
        echo "Has intensity column: $HAS_INTENSITY_COL"
        echo "Segments found: $SEGMENTS_FOUND"
    fi
    
    # Copy CSV to /tmp for verifier
    cp "$CSV_PATH" /tmp/exported_statistics.csv 2>/dev/null || true
fi

# ============================================================
# Get window information for VLM verification
# ============================================================
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
SEGMENT_STATS_WINDOW="false"
if echo "$WINDOWS_LIST" | grep -qi "Segment Statistics\|SegmentStatistics"; then
    SEGMENT_STATS_WINDOW="true"
fi

# ============================================================
# Get sample ID
# ============================================================
SAMPLE_ID=$(cat /tmp/task_sample_id 2>/dev/null || echo "unknown")

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Save extracted data separately
if [ -n "$EXTRACTED_DATA" ]; then
    echo "$EXTRACTED_DATA" > /tmp/csv_parsed_data.json
fi

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "sample_id": "$SAMPLE_ID",
    "slicer_was_running": $SLICER_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_path": "$CSV_PATH",
    "csv_size_bytes": $CSV_SIZE_BYTES,
    "csv_mtime": $CSV_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "csv_valid": $CSV_VALID,
    "num_rows": $NUM_ROWS,
    "num_cols": $NUM_COLS,
    "has_segment_col": $HAS_SEGMENT_COL,
    "has_volume_col": $HAS_VOLUME_COL,
    "has_intensity_col": $HAS_INTENSITY_COL,
    "segments_found": "$SEGMENTS_FOUND",
    "segment_stats_window_visible": $SEGMENT_STATS_WINDOW,
    "screenshot_path": "/tmp/segstats_final.png"
}
EOF

# Move to final location
rm -f /tmp/segstats_result.json 2>/dev/null || sudo rm -f /tmp/segstats_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/segstats_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/segstats_result.json
chmod 666 /tmp/segstats_result.json 2>/dev/null || sudo chmod 666 /tmp/segstats_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/segstats_result.json"
cat /tmp/segstats_result.json
echo ""
echo "=== Export Complete ==="