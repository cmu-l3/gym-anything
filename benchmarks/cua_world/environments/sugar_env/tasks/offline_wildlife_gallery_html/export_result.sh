#!/bin/bash
echo "=== Exporting task results ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Capture final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
HTML_PATH="/home/ga/Documents/wildlife_gallery/index.html"

HTML_MODIFIED="false"
if [ -f "$HTML_PATH" ]; then
    HTML_MTIME=$(stat -c %Y "$HTML_PATH" 2>/dev/null || echo "0")
    if [ "$HTML_MTIME" -gt "$TASK_START" ]; then
        HTML_MODIFIED="true"
    fi
fi

# Run a Python analyzer script to parse HTML and verify image dimensions 
python3 << 'PYEOF' > /tmp/gallery_result_raw.json 2>/dev/null || echo '{"error": "parse_failed"}' > /tmp/gallery_result_raw.json
import json
import os
import re

# Safely import Pillow, installing it if necessary
try:
    from PIL import Image
except ImportError:
    import sys
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"])
    from PIL import Image

result = {
    "html_exists": False,
    "heading_found": False,
    "thumb_count": 0,
    "thumbs_valid_size": False,
    "img_tags": [],
    "a_tags": []
}

expected_files = ["monarch_butterfly.jpg", "red_eyed_tree_frog.jpg", "galapagos_tortoise.jpg"]
thumbs_dir = "/home/ga/Documents/wildlife_gallery/thumbs"

valid_thumbs = 0
sizes_ok = True

# Validate dimensions of thumbnails
if os.path.isdir(thumbs_dir):
    for fname in expected_files:
        path = os.path.join(thumbs_dir, fname)
        if os.path.exists(path):
            valid_thumbs += 1
            try:
                with Image.open(path) as img:
                    w, h = img.size
                    if w > 200 or h > 200:
                        sizes_ok = False
            except Exception:
                sizes_ok = False

result["thumb_count"] = valid_thumbs
result["thumbs_valid_size"] = sizes_ok and valid_thumbs > 0

html_path = "/home/ga/Documents/wildlife_gallery/index.html"
if os.path.exists(html_path):
    result["html_exists"] = True
    try:
        with open(html_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
        result["heading_found"] = "wildlife gallery" in content.lower()
        
        # Regex extraction of image sources and anchor references
        imgs = re.findall(r'<img[^>]+src=[\'"]([^\'"]+)[\'"]', content, re.IGNORECASE)
        result["img_tags"] = imgs
        
        links = re.findall(r'<a[^>]+href=[\'"]([^\'"]+)[\'"]', content, re.IGNORECASE)
        result["a_tags"] = links
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Merge the timestamp modification boolean with the python JSON blob
cat /tmp/gallery_result_raw.json | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except:
    data = {}
data['html_modified'] = '$HTML_MODIFIED' == 'true'
print(json.dumps(data, indent=2))
" > /tmp/task_result.json

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="