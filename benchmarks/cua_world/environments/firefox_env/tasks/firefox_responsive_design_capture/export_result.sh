#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

MOBILE_IMG="/home/ga/Documents/QA_Screenshots/mobile_viewport.png"
TABLET_IMG="/home/ga/Documents/QA_Screenshots/tablet_viewport.png"

# Collect info for mobile
if [ -f "$MOBILE_IMG" ]; then
    MOBILE_EXISTS="true"
    MOBILE_MTIME=$(stat -c %Y "$MOBILE_IMG" 2>/dev/null || echo "0")
    if [ "$MOBILE_MTIME" -gt "$TASK_START" ]; then
        MOBILE_CREATED_DURING="true"
    else
        MOBILE_CREATED_DURING="false"
    fi
    MOBILE_SIZE=$(stat -c %s "$MOBILE_IMG" 2>/dev/null || echo "0")
    
    # Get dimensions
    DIMENSIONS=$(python3 -c "from PIL import Image; img=Image.open('$MOBILE_IMG'); print(f'{img.width}x{img.height}')" 2>/dev/null || echo "0x0")
    MOBILE_WIDTH=$(echo "$DIMENSIONS" | cut -d'x' -f1)
    MOBILE_HEIGHT=$(echo "$DIMENSIONS" | cut -d'x' -f2)
else
    MOBILE_EXISTS="false"
    MOBILE_CREATED_DURING="false"
    MOBILE_SIZE="0"
    MOBILE_WIDTH="0"
    MOBILE_HEIGHT="0"
fi

# Collect info for tablet
if [ -f "$TABLET_IMG" ]; then
    TABLET_EXISTS="true"
    TABLET_MTIME=$(stat -c %Y "$TABLET_IMG" 2>/dev/null || echo "0")
    if [ "$TABLET_MTIME" -gt "$TASK_START" ]; then
        TABLET_CREATED_DURING="true"
    else
        TABLET_CREATED_DURING="false"
    fi
    TABLET_SIZE=$(stat -c %s "$TABLET_IMG" 2>/dev/null || echo "0")
    
    DIMENSIONS=$(python3 -c "from PIL import Image; img=Image.open('$TABLET_IMG'); print(f'{img.width}x{img.height}')" 2>/dev/null || echo "0x0")
    TABLET_WIDTH=$(echo "$DIMENSIONS" | cut -d'x' -f1)
    TABLET_HEIGHT=$(echo "$DIMENSIONS" | cut -d'x' -f2)
else
    TABLET_EXISTS="false"
    TABLET_CREATED_DURING="false"
    TABLET_SIZE="0"
    TABLET_WIDTH="0"
    TABLET_HEIGHT="0"
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "mobile": {
        "exists": $MOBILE_EXISTS,
        "created_during_task": $MOBILE_CREATED_DURING,
        "size_bytes": $MOBILE_SIZE,
        "width": $MOBILE_WIDTH,
        "height": $MOBILE_HEIGHT
    },
    "tablet": {
        "exists": $TABLET_EXISTS,
        "created_during_task": $TABLET_CREATED_DURING,
        "size_bytes": $TABLET_SIZE,
        "width": $TABLET_WIDTH,
        "height": $TABLET_HEIGHT
    }
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="