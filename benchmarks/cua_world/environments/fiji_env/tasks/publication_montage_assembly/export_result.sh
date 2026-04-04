#!/bin/bash
echo "=== Exporting Publication Montage Results ==="

# Record end time and read start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/Fiji_Data/results/montage"

# Take final screenshot of the desktop state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file existence and timestamps
check_file() {
    local file=$1
    if [ -f "$file" ]; then
        local mtime=$(stat -c %Y "$file")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false" # Exists but old
        fi
    else
        echo "false"
    fi
}

MONTAGE_PNG_EXISTS=$(check_file "$OUTPUT_DIR/figure_montage.png")
MONTAGE_TIF_EXISTS=$(check_file "$OUTPUT_DIR/figure_montage.tif")
METADATA_CSV_EXISTS=$(check_file "$OUTPUT_DIR/panel_metadata.csv")
STATS_CSV_EXISTS=$(check_file "$OUTPUT_DIR/panel_statistics.csv")

# Use Python to inspect the content of the CSVs and JSON-ify the result
# This runs inside the container
python3 << PYEOF
import json
import os
import csv
import sys

output_dir = "$OUTPUT_DIR"
result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "montage_png_created": $MONTAGE_PNG_EXISTS,
    "montage_tif_created": $MONTAGE_TIF_EXISTS,
    "metadata_csv_created": $METADATA_CSV_EXISTS,
    "stats_csv_created": $STATS_CSV_EXISTS,
    "metadata_rows": [],
    "stats_rows": [],
    "png_size": 0,
    "tif_size": 0
}

# Inspect PNG size
png_path = os.path.join(output_dir, "figure_montage.png")
if os.path.exists(png_path):
    result["png_size"] = os.path.getsize(png_path)

# Inspect TIF size
tif_path = os.path.join(output_dir, "figure_montage.tif")
if os.path.exists(tif_path):
    result["tif_size"] = os.path.getsize(tif_path)

# Parse Metadata CSV
meta_path = os.path.join(output_dir, "panel_metadata.csv")
if os.path.exists(meta_path):
    try:
        with open(meta_path, 'r') as f:
            reader = csv.DictReader(f)
            result["metadata_rows"] = list(reader)
    except Exception as e:
        result["metadata_error"] = str(e)

# Parse Statistics CSV
stats_path = os.path.join(output_dir, "panel_statistics.csv")
if os.path.exists(stats_path):
    try:
        with open(stats_path, 'r') as f:
            reader = csv.DictReader(f)
            result["stats_rows"] = list(reader)
    except Exception as e:
        result["stats_error"] = str(e)

# Save result to /tmp/task_result.json
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

PYEOF

# Copy result files to /tmp for easy retrieval by verifier
if [ -f "$OUTPUT_DIR/figure_montage.png" ]; then
    cp "$OUTPUT_DIR/figure_montage.png" /tmp/figure_montage.png
fi

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="