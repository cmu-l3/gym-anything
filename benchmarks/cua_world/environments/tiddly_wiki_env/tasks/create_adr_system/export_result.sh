#!/bin/bash
echo "=== Exporting create_adr_system result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/adr_final.png

# Use Python to safely extract data from .tid files and generate verification JSON
cat << 'PYEOF' > /tmp/export_adrs.py
import os
import json

tiddler_dir = "/home/ga/mywiki/tiddlers"
result = {
    "tiddlers": {},
    "gui_save_detected": False
}

if os.path.exists(tiddler_dir):
    for filename in os.listdir(tiddler_dir):
        if not filename.endswith('.tid'): continue
        if filename.startswith('$__'): continue
        
        filepath = os.path.join(tiddler_dir, filename)
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # TiddlyWiki uses a double newline to separate metadata fields from the body
            parts = content.split('\n\n', 1)
            header = parts[0]
            body = parts[1] if len(parts) > 1 else ""
            
            fields = {}
            for line in header.split('\n'):
                if ':' in line:
                    k, v = line.split(':', 1)
                    fields[k.strip()] = v.strip()
                    
            title = fields.get('title', filename.replace('.tid', ''))
            
            result['tiddlers'][title] = {
                'tags': fields.get('tags', ''),
                'adr_status': fields.get('adr-status', ''),
                'body': body
            }
        except Exception as e:
            pass

# Check TiddlyWiki server logs for evidence of GUI interaction (anti-gaming)
try:
    with open('/home/ga/tiddlywiki.log', 'r') as f:
        log = f.read()
        if "Dispatching 'save' task:" in log and "ADR" in log:
            result['gui_save_detected'] = True
except Exception:
    pass

with open('/tmp/adr_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

python3 /tmp/export_adrs.py

echo "Result saved to /tmp/adr_result.json"
cat /tmp/adr_result.json
echo "=== Export complete ==="