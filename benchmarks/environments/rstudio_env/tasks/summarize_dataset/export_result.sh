#!/bin/bash
echo "=== Exporting task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get task start time
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Paths
OUTPUT_PATH="/home/ga/RProjects/output/species_summary.csv"
SCRIPT_PATH="/home/ga/RProjects/summary_analysis.R"
DATASET_PATH="/home/ga/RProjects/datasets/penguins.csv"

# Check output file
OUTPUT_EXISTS="false"
OUTPUT_SIZE_BYTES=0
OUTPUT_ROWS=0
OUTPUT_COLS=""
HAS_SPECIES_COL="false"
HAS_MEAN_COL="false"
HAS_SD_COL="false"
HAS_ALL_SPECIES="false"
OUTPUT_CREATED="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE_BYTES=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    # Use awk to count rows properly (handles missing final newline)
    OUTPUT_ROWS=$(awk 'END {print NR}' "$OUTPUT_PATH" 2>/dev/null || echo "0")

    # Get column names (first line) - remove quotes for JSON safety
    OUTPUT_COLS=$(head -1 "$OUTPUT_PATH" 2>/dev/null | tr ',' ' ' | tr -d '"')

    # Check for required columns
    if echo "$OUTPUT_COLS" | grep -qi "species"; then
        HAS_SPECIES_COL="true"
    fi
    if echo "$OUTPUT_COLS" | grep -qi "mean"; then
        HAS_MEAN_COL="true"
    fi
    if echo "$OUTPUT_COLS" | grep -qi "sd"; then
        HAS_SD_COL="true"
    fi

    # Check if all species are present
    if grep -qi "adelie" "$OUTPUT_PATH" && grep -qi "chinstrap" "$OUTPUT_PATH" && grep -qi "gentoo" "$OUTPUT_PATH"; then
        HAS_ALL_SPECIES="true"
    fi

    # Check if file was created after task start
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED="true"
    fi
fi

# Check R script
SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
HAS_READ_CSV="false"
HAS_DPLYR="false"
HAS_GROUP_BY="false"
HAS_SUMMARIZE="false"
HAS_WRITE_CSV="false"
HAS_BODY_MASS="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_CONTENT=$(cat "$SCRIPT_PATH" 2>/dev/null)

    # Check if script was modified
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi

    # Check script content - exclude comment lines to avoid false positives
    CODE_ONLY=$(echo "$SCRIPT_CONTENT" | grep -v '^\s*#')

    if echo "$CODE_ONLY" | grep -qi "read\.csv\s*(\|read_csv\s*("; then
        HAS_READ_CSV="true"
    fi
    # Check for dplyr usage: library(), require(), namespace prefix, or pipe operator
    if echo "$CODE_ONLY" | grep -Ei "library\s*\(\s*dplyr|library\s*\(\s*tidyverse|require\s*\(\s*dplyr|require\s*\(\s*tidyverse|dplyr::|tidyverse::|%>%|\|>" > /dev/null; then
        HAS_DPLYR="true"
    fi
    if echo "$CODE_ONLY" | grep -qi "group_by\s*("; then
        HAS_GROUP_BY="true"
    fi
    if echo "$CODE_ONLY" | grep -qi "summarize\s*(\|summarise\s*("; then
        HAS_SUMMARIZE="true"
    fi
    if echo "$CODE_ONLY" | grep -qi "write\.csv\s*(\|write_csv\s*("; then
        HAS_WRITE_CSV="true"
    fi
    if echo "$CODE_ONLY" | grep -qi "body_mass"; then
        HAS_BODY_MASS="true"
    fi
fi

# Check if RStudio is running
RSTUDIO_RUNNING="false"
if pgrep -f "rstudio" > /dev/null 2>&1; then
    RSTUDIO_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE_BYTES,
    "output_rows": $OUTPUT_ROWS,
    "output_columns": "$OUTPUT_COLS",
    "output_created": $OUTPUT_CREATED,
    "has_species_col": $HAS_SPECIES_COL,
    "has_mean_col": $HAS_MEAN_COL,
    "has_sd_col": $HAS_SD_COL,
    "has_all_species": $HAS_ALL_SPECIES,
    "script_exists": $SCRIPT_EXISTS,
    "script_modified": $SCRIPT_MODIFIED,
    "has_read_csv": $HAS_READ_CSV,
    "has_dplyr": $HAS_DPLYR,
    "has_group_by": $HAS_GROUP_BY,
    "has_summarize": $HAS_SUMMARIZE,
    "has_write_csv": $HAS_WRITE_CSV,
    "has_body_mass": $HAS_BODY_MASS,
    "rstudio_running": $RSTUDIO_RUNNING,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
