#!/bin/bash
echo "=== Exporting build_dichotomous_key_and_log result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/dichotomous_key_final.png

# Extract all relevant tiddler data using an inline Python script
# This ensures robust parsing of the TiddlyWiki file format
cat > /tmp/extract_tiddlers.py << 'EOF'
import os
import json
import re

TIDDLER_DIR = "/home/ga/mywiki/tiddlers"
result = {
    "tiddlers": {},
    "gui_saves": 0,
    "timestamp": 0
}

# Parse Tiddler files
if os.path.exists(TIDDLER_DIR):
    for fn in os.listdir(TIDDLER_DIR):
        if fn.endswith('.tid') and not fn.startswith('$__'):
            path = os.path.join(TIDDLER_DIR, fn)
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                parts = content.split('\n\n', 1)
                frontmatter = parts[0]
                body = parts[1] if len(parts) > 1 else ""
                
                fields = {}
                for line in frontmatter.split('\n'):
                    if ':' in line:
                        k, v = line.split(':', 1)
                        fields[k.strip().lower()] = v.strip()
                
                title = fields.get('title', fn[:-4])
                
                # Check file modification time
                mtime = os.path.getmtime(path)
                
                result["tiddlers"][title] = {
                    "fields": fields,
                    "body": body,
                    "mtime": mtime
                }
            except Exception as e:
                pass

# Check TiddlyWiki server log for GUI save events (anti-gaming check)
try:
    with open('/home/ga/tiddlywiki.log', 'r', encoding='utf-8') as f:
        log = f.read()
        result["gui_saves"] = len(re.findall(r"Dispatching 'save' task:", log))
except Exception:
    pass

import time
result["timestamp"] = time.time()

with open("/tmp/dichotomous_key_result.json", "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2)

EOF

python3 /tmp/extract_tiddlers.py

# Ensure permissions
chmod 666 /tmp/dichotomous_key_result.json 2>/dev/null || sudo chmod 666 /tmp/dichotomous_key_result.json 2>/dev/null || true

echo "Result saved to /tmp/dichotomous_key_result.json"
echo "=== Export complete ==="