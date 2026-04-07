#!/bin/bash
echo "=== Exporting task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/factsheet_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/factsheet_task_start_ts 2>/dev/null || echo "0")
IMAGE_FILE="/home/ga/Documents/capybara_500px.jpg"
ODT_FILE="/home/ga/Documents/capybara_factsheet.odt"

# Check the optimized image file
IMAGE_EXISTS="false"
IMAGE_MODIFIED="false"
IMAGE_WIDTH=0

if [ -f "$IMAGE_FILE" ]; then
    IMAGE_EXISTS="true"
    IMAGE_MTIME=$(stat --format=%Y "$IMAGE_FILE" 2>/dev/null || echo "0")
    if [ "$IMAGE_MTIME" -gt "$TASK_START" ]; then
        IMAGE_MODIFIED="true"
    fi
    # Use ImageMagick 'identify' to get width
    IMAGE_WIDTH=$(identify -format "%w" "$IMAGE_FILE" 2>/dev/null || echo "0")
fi

# Check the ODT file
ODT_EXISTS="false"
ODT_MODIFIED="false"
ODT_SIZE=0

if [ -f "$ODT_FILE" ]; then
    ODT_EXISTS="true"
    ODT_SIZE=$(stat --format=%s "$ODT_FILE" 2>/dev/null || echo "0")
    ODT_MTIME=$(stat --format=%Y "$ODT_FILE" 2>/dev/null || echo "0")
    if [ "$ODT_MTIME" -gt "$TASK_START" ]; then
        ODT_MODIFIED="true"
    fi

    # Parse ODT using Python
    python3 << 'PYEOF' > /tmp/odt_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/odt_analysis.json
import json
import zipfile
import re

result = {
    "has_title": False,
    "has_cavy": False,
    "has_rodent": False,
    "has_south_america": False,
    "has_image_embedded": False,
    "embedded_image_size": 0,
    "error": None
}

odt_file = "/home/ga/Documents/capybara_factsheet.odt"

try:
    with zipfile.ZipFile(odt_file, 'r') as z:
        # Check text content
        with z.open('content.xml') as f:
            content = f.read().decode('utf-8')
            plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
            plain_text = plain_text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
            
            # Allow case insensitivity and flexible spacing
            result["has_title"] = bool(re.search(r'animal\s+fact\s+sheet[:\s]+capybara', plain_text))
            result["has_cavy"] = bool(re.search(r'\bcavy\b', plain_text))
            result["has_rodent"] = bool(re.search(r'\brodent\b', plain_text))
            result["has_south_america"] = bool(re.search(r'\bsouth\s+america\b', plain_text))

        # Check embedded images
        pictures = [name for name in z.namelist() if name.startswith('Pictures/') and name != 'Pictures/']
        if pictures:
            result["has_image_embedded"] = True
            # Get the size of the largest embedded picture
            max_size = 0
            for pic in pictures:
                info = z.getinfo(pic)
                if info.file_size > max_size:
                    max_size = info.file_size
            result["embedded_image_size"] = max_size

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

else:
    echo '{"error":"file_not_found"}' > /tmp/odt_analysis.json
fi

# Combine into task result
cat > /tmp/factsheet_task_result.json << EOF
{
    "image_exists": $IMAGE_EXISTS,
    "image_modified": $IMAGE_MODIFIED,
    "image_width": $IMAGE_WIDTH,
    "odt_exists": $ODT_EXISTS,
    "odt_modified": $ODT_MODIFIED,
    "odt_size": $ODT_SIZE,
    "odt_analysis": $(cat /tmp/odt_analysis.json)
}
EOF

chmod 666 /tmp/factsheet_task_result.json
echo "Result saved to /tmp/factsheet_task_result.json"
cat /tmp/factsheet_task_result.json
echo "=== Export complete ==="