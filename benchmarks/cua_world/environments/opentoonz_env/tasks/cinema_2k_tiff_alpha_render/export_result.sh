#!/bin/bash
echo "=== Exporting cinema_2k_tiff_alpha_render result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/cinema_2k_tiff"
TASK_START=$(cat /tmp/task_start_timestamp.txt 2>/dev/null || echo "0")

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# 2. Analyze Output Files
# We look for .tif or .tiff files
TIFF_FILES=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name "*.tif" -o -name "*.tiff" \) -type f 2>/dev/null)
FILE_COUNT=$(echo "$TIFF_FILES" | grep -v "^$" | wc -l)
FIRST_FILE=$(echo "$TIFF_FILES" | head -n 1)

# Initialize analysis variables
IMG_WIDTH=0
IMG_HEIGHT=0
IMG_FORMAT="NONE"
IMG_MODE="NONE"
FILES_NEWER=0
TOTAL_SIZE_KB=0

if [ -n "$FIRST_FILE" ]; then
    # Use Python/PIL to inspect the first image strictly
    # We need to know: Resolution, Format, and if it has Alpha (Mode=RGBA)
    ANALYSIS=$(python3 -c "
import sys
from PIL import Image
try:
    img = Image.open(sys.argv[1])
    # Output: WIDTH HEIGHT FORMAT MODE
    print(f'{img.width} {img.height} {img.format} {img.mode}')
except Exception as e:
    print('0 0 ERROR NONE')
" "$FIRST_FILE" 2>/dev/null)
    
    IMG_WIDTH=$(echo "$ANALYSIS" | awk '{print $1}')
    IMG_HEIGHT=$(echo "$ANALYSIS" | awk '{print $2}')
    IMG_FORMAT=$(echo "$ANALYSIS" | awk '{print $3}')
    IMG_MODE=$(echo "$ANALYSIS" | awk '{print $4}')
    
    # Check timestamp of files
    FILES_NEWER=$(find "$OUTPUT_DIR" -type f -newer /tmp/task_start_timestamp.txt 2>/dev/null | wc -l)
    
    # Check directory size
    TOTAL_SIZE_KB=$(du -sk "$OUTPUT_DIR" | cut -f1)
fi

# 3. Create JSON Result
# We use a temp file to avoid permission issues, then move it
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_count": $FILE_COUNT,
    "first_file_name": "$(basename "$FIRST_FILE" 2>/dev/null || echo "")",
    "img_width": $IMG_WIDTH,
    "img_height": $IMG_HEIGHT,
    "img_format": "$IMG_FORMAT",
    "img_mode": "$IMG_MODE",
    "files_created_during_task": $FILES_NEWER,
    "total_size_kb": $TOTAL_SIZE_KB,
    "task_start_timestamp": $TASK_START,
    "output_dir_exists": $([ -d "$OUTPUT_DIR" ] && echo "true" || echo "false")
}
EOF

# Move to standard location with lenient permissions
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json