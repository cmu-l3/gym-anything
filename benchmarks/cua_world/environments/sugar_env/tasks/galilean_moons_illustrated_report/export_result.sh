#!/bin/bash
echo "=== Exporting galilean_moons_illustrated_report result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

su - ga -c "$SUGAR_ENV scrot /tmp/galilean_moons_end.png" 2>/dev/null || true

ODT_FILE="/home/ga/Documents/jupiter_moons.odt"
TASK_START=$(cat /tmp/galilean_moons_start_ts 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MODIFIED="false"

if [ -f "$ODT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$ODT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$ODT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# We use python to parse the ODT file (ZIP archive containing content.xml)
cat << 'PYEOF' > /tmp/parse_odt.py
import json
import zipfile
import re
import sys

result = {
    "plain_text": "",
    "image_count": 0,
    "error": None
}

odt_file = "/home/ga/Documents/jupiter_moons.odt"
try:
    with zipfile.ZipFile(odt_file, 'r') as z:
        if 'content.xml' in z.namelist():
            with z.open('content.xml') as f:
                content = f.read().decode('utf-8')
            
            # Count images
            result["image_count"] = content.count('<draw:image')
            
            # Strip XML tags to get plain text
            plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
            plain_text = plain_text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
            result["plain_text"] = plain_text
        else:
            result["error"] = "No content.xml found"
except Exception as e:
    result["error"] = str(e)

with open("/tmp/parsed_odt.json", "w") as f:
    json.dump(result, f)
PYEOF

if [ "$FILE_EXISTS" = "true" ]; then
    python3 /tmp/parse_odt.py
else
    echo '{"plain_text": "", "image_count": 0, "error": "file_not_found"}' > /tmp/parsed_odt.json
fi

# Combine results into final JSON
cat > /tmp/galilean_moons_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "parsed": $(cat /tmp/parsed_odt.json)
}
EOF

chmod 666 /tmp/galilean_moons_result.json
echo "Result saved to /tmp/galilean_moons_result.json"
cat /tmp/galilean_moons_result.json
echo "=== Export complete ==="