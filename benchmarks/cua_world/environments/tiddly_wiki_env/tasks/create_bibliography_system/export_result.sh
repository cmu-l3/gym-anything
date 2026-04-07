#!/bin/bash
set -e
echo "=== Exporting Bibliography System result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Get system state variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_tiddler_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers 2>/dev/null || echo "0")

# Check GUI saves in logs
GUI_SAVES=$(grep -c "Dispatching 'save' task:" /home/ga/tiddlywiki.log 2>/dev/null || echo "0")

# Execute a Python script to parse the TiddlyWiki .tid files accurately
# This handles title normalization, field parsing, and avoids bash escaping nightmares
python3 << PYEOF
import json
import os
import re

tiddler_dir = "/home/ga/mywiki/tiddlers"
task_start = int("$TASK_START")

def parse_tid(filepath):
    """Parse a .tid file into a dictionary of fields and text."""
    fields = {}
    text_lines = []
    
    if not os.path.isfile(filepath):
        return None
        
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.readlines()
            
        in_body = False
        for line in lines:
            if in_body:
                text_lines.append(line)
            elif line.strip() == '':
                in_body = True
            else:
                if ':' in line:
                    key, val = line.split(':', 1)
                    fields[key.strip().lower()] = val.strip()
                    
        fields['text'] = ''.join(text_lines)
        fields['__mtime'] = os.path.getmtime(filepath)
        fields['__created_during_task'] = fields['__mtime'] >= task_start
        return fields
    except Exception as e:
        return {"error": str(e)}

result = {
    "metrics": {
        "initial_count": int("$INITIAL_COUNT"),
        "current_count": int("$CURRENT_COUNT"),
        "task_start_time": task_start,
        "gui_saves": int("$GUI_SAVES")
    },
    "tiddlers": {}
}

# Scan all user tiddlers
if os.path.isdir(tiddler_dir):
    for filename in os.listdir(tiddler_dir):
        if filename.endswith(".tid") and not filename.startswith("$__"):
            filepath = os.path.join(tiddler_dir, filename)
            parsed = parse_tid(filepath)
            if parsed and "title" in parsed:
                # Store by title for easy lookup in verifier
                result["tiddlers"][parsed["title"]] = parsed

# Write the final JSON result
with open("/tmp/bibliography_result.json", "w", encoding="utf-8") as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/bibliography_result.json 2>/dev/null || true
echo "Result JSON saved to /tmp/bibliography_result.json"
cat /tmp/bibliography_result.json
echo "=== Export complete ==="