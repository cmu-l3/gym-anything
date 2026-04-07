#!/bin/bash
echo "=== Exporting relink_offline_media_render result ==="

OUTPUT_DIR="/home/ga/OpenToonz/output/relink_test"
OUTPUT_FILE="$OUTPUT_DIR/fixed_frame.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Output File Existence
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE")
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
fi

# 2. Check Timestamp (Anti-gaming)
if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
else
    FILE_CREATED_DURING_TASK="false"
fi

# 3. Check Image Properties (Resolution & Color Variance)
# We use Python to check if the image is blank/solid color (indicating missing media/render error)
IMG_INFO=$(python3 -c "
import sys, json
from PIL import Image, ImageStat
try:
    if '$OUTPUT_EXISTS' != 'true':
        print(json.dumps({'valid': False}))
        sys.exit(0)
        
    img = Image.open('$OUTPUT_FILE')
    stat = ImageStat.Stat(img)
    
    # Check for solid color (variance is 0)
    # Some variance is expected if actual content is rendered
    variance = sum(stat.var) / len(stat.var) if stat.var else 0
    
    # Check if it looks like the red 'missing media' placeholder
    # (OpenToonz sometimes renders missing regions as red or pink)
    # Simple heuristic: is it mostly red?
    r, g, b = 0, 0, 0
    if img.mode == 'RGB' or img.mode == 'RGBA':
        img_rgb = img.convert('RGB')
        # pixel = img_rgb.getpixel((img.width//2, img.height//2))
        # better: verify it's NOT solid red
        pass

    print(json.dumps({
        'valid': True,
        'width': img.width,
        'height': img.height,
        'variance': variance,
        'format': img.format
    }))
except Exception as e:
    print(json.dumps({'valid': False, 'error': str(e)}))
" 2>/dev/null || echo '{"valid": false}')

# 4. Check App State
APP_RUNNING=$(pgrep -f "opentoonz" > /dev/null && echo "true" || echo "false")

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "img_info": $IMG_INFO,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="