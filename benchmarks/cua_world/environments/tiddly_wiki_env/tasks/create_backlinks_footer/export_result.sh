#!/bin/bash
echo "=== Exporting create_backlinks_footer result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Fetch the final HTML render of the test tiddlers via API
# This lets us programmatically check what the UI actually looks like!
curl -s "http://localhost:8080/recipes/default/tiddlers/Evergreen%20Notes.html" > /tmp/linked_final.html
curl -s "http://localhost:8080/recipes/default/tiddlers/Orphan%20Note.html" > /tmp/orphan_final.html

# Use Python to safely parse filesystem, API results, and server logs into a JSON result
python3 << 'EOF'
import json
import os
import glob
import re

TIDDLER_DIR = "/home/ga/mywiki/tiddlers"
TASK_START = int(os.environ.get('TASK_START', 0))

result = {
    "template_found": False,
    "template_file": "",
    "template_content": "",
    "template_tags": "",
    "linked_note_html": "",
    "orphan_note_html": "",
    "gui_save_detected": False
}

# 1. Find the newly created ViewTemplate tiddler
try:
    candidate_files = []
    for filepath in glob.glob(f"{TIDDLER_DIR}/**/*.tid", recursive=True):
        stat = os.stat(filepath)
        if stat.st_mtime >= TASK_START:
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
                # Check if it has the ViewTemplate tag and isn't a core override
                if "$:/tags/ViewTemplate" in content and "core/ui" not in filepath:
                    candidate_files.append((filepath, content))
    
    if candidate_files:
        # Pick the most recently modified candidate
        candidate_files.sort(key=lambda x: os.path.getmtime(x[0]), reverse=True)
        best_file, best_content = candidate_files[0]
        
        result["template_found"] = True
        result["template_file"] = best_file
        result["template_content"] = best_content
        
        # Extract tags line
        for line in best_content.split('\n'):
            if line.startswith('tags:'):
                result["template_tags"] = line
                break
except Exception as e:
    result["error_finding_template"] = str(e)

# 2. Read the rendered HTML pages
try:
    with open('/tmp/linked_final.html', 'r', encoding='utf-8') as f:
        result["linked_note_html"] = f.read()
    with open('/tmp/orphan_final.html', 'r', encoding='utf-8') as f:
        result["orphan_note_html"] = f.read()
except Exception as e:
    pass

# 3. Check for GUI interaction in the TiddlyWiki server log
try:
    with open('/home/ga/tiddlywiki.log', 'r', encoding='utf-8') as f:
        log_content = f.read()
        # Look for saves of the view template
        if re.search(r"Dispatching 'save' task:.*ViewTemplate", log_content, re.IGNORECASE):
            result["gui_save_detected"] = True
except Exception:
    pass

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

# Ensure permissions are open for the host to read
chmod 666 /tmp/task_result.json

echo "Result exported successfully."
cat /tmp/task_result.json
echo "=== Export complete ==="