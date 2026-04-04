#!/bin/bash
echo "=== Exporting task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get task start time
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Paths
OUTPUT_PATH="/home/ga/RProjects/output/penguin_scatter.png"
SCRIPT_PATH="/home/ga/RProjects/analysis.R"
DATASET_PATH="/home/ga/RProjects/datasets/penguins.csv"

# Check output file
OUTPUT_EXISTS="false"
OUTPUT_SIZE_KB=0
OUTPUT_DIMENSIONS=""
OUTPUT_CREATED="false"
OUTPUT_MODIFIED="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE_KB=$(du -k "$OUTPUT_PATH" 2>/dev/null | cut -f1)

    # Get image dimensions using ImageMagick
    OUTPUT_DIMENSIONS=$(identify -format "%wx%h" "$OUTPUT_PATH" 2>/dev/null || echo "unknown")

    # Check if file was created/modified after task start
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED="true"
        OUTPUT_MODIFIED="true"
    fi
fi

# Check R script
SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
SCRIPT_CONTENT=""
HAS_READ_CSV="false"
HAS_GGPLOT="false"
HAS_GEOM_POINT="false"
HAS_GGSAVE="false"
HAS_FLIPPER_LENGTH="false"
HAS_BODY_MASS="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_CONTENT=$(cat "$SCRIPT_PATH" 2>/dev/null)

    # Check if script was modified after task start
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi

    # Check script content for required elements - exclude comment lines
    # Filter out lines starting with # to avoid matching keywords in comments
    CODE_ONLY=$(echo "$SCRIPT_CONTENT" | grep -v '^\s*#')

    if echo "$CODE_ONLY" | grep -qi "read\.csv\s*(\|read_csv\s*(\|fread\s*("; then
        HAS_READ_CSV="true"
    fi
    if echo "$CODE_ONLY" | grep -qi "ggplot\s*("; then
        HAS_GGPLOT="true"
    fi
    if echo "$CODE_ONLY" | grep -qi "geom_point\s*("; then
        HAS_GEOM_POINT="true"
    fi
    if echo "$CODE_ONLY" | grep -qi "ggsave\s*(\|png\s*(\|pdf\s*("; then
        HAS_GGSAVE="true"
    fi
    if echo "$CODE_ONLY" | grep -qi "flipper_length"; then
        HAS_FLIPPER_LENGTH="true"
    fi
    if echo "$CODE_ONLY" | grep -qi "body_mass"; then
        HAS_BODY_MASS="true"
    fi
fi

# Check if RStudio was running
RSTUDIO_RUNNING="false"
if pgrep -f "rstudio" > /dev/null 2>&1; then
    RSTUDIO_RUNNING="true"
fi

# Check dataset
DATASET_EXISTS="false"
DATASET_ROWS=0
if [ -f "$DATASET_PATH" ]; then
    DATASET_EXISTS="true"
    DATASET_ROWS=$(wc -l < "$DATASET_PATH" 2>/dev/null || echo "0")
fi

# Create JSON result in temp file first
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "output_size_kb": $OUTPUT_SIZE_KB,
    "output_dimensions": "$OUTPUT_DIMENSIONS",
    "output_created": $OUTPUT_CREATED,
    "output_modified": $OUTPUT_MODIFIED,
    "script_exists": $SCRIPT_EXISTS,
    "script_modified": $SCRIPT_MODIFIED,
    "has_read_csv": $HAS_READ_CSV,
    "has_ggplot": $HAS_GGPLOT,
    "has_geom_point": $HAS_GEOM_POINT,
    "has_ggsave": $HAS_GGSAVE,
    "has_flipper_length": $HAS_FLIPPER_LENGTH,
    "has_body_mass": $HAS_BODY_MASS,
    "rstudio_running": $RSTUDIO_RUNNING,
    "dataset_exists": $DATASET_EXISTS,
    "dataset_rows": $DATASET_ROWS,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
