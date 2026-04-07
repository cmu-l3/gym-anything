#!/bin/bash
echo "=== Exporting create_interactive_search_app result ==="

source /workspace/scripts/task_utils.sh

WIKI_DIR="/home/ga/mywiki"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Perform Behavioral Simulation (Anti-Gaming check)
# 1. Inject the state tiddler simulating user input "Bleeding"
cat > "$WIKI_DIR/tiddlers/\$__temp_drug-search.tid" << 'EOF'
title: $:/temp/drug-search
type: text/vnd.tiddlywiki

Bleeding
EOF
chown ga:ga "$WIKI_DIR/tiddlers/\$__temp_drug-search.tid"

# 2. Render the dashboard tiddler to plain text to see the reactive output
RENDER_SUCCESS="false"
su - ga -c "cd $WIKI_DIR && tiddlywiki . --render 'Drug Interaction Finder' 'dashboard_test.txt' 'text/plain'" 2>/dev/null && RENDER_SUCCESS="true"

# Wait for output to generate
sleep 2

# Use Python to safely package all data into JSON, avoiding bash escaping nightmares
python3 << 'PYEOF'
import json
import os
import glob
import re

wiki_dir = "/home/ga/mywiki"
tiddler_dir = os.path.join(wiki_dir, "tiddlers")
result_file = "/tmp/search_app_result.json"

# Safely find the dashboard tiddler by checking titles (to handle file naming variations)
dashboard_path = None
for filepath in glob.glob(os.path.join(tiddler_dir, "*.tid")):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
            if re.search(r'^title:\s*Drug Interaction Finder\s*$', content, re.MULTILINE):
                dashboard_path = filepath
                break
    except Exception:
        pass

dashboard_exists = dashboard_path is not None
dashboard_text = ""
dashboard_tags = ""
creation_time = 0

if dashboard_exists:
    creation_time = os.path.getmtime(dashboard_path)
    with open(dashboard_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    # Extract tags
    tag_match = re.search(r'^tags:\s*(.+)$', content, re.MULTILINE)
    if tag_match:
        dashboard_tags = tag_match.group(1).strip()
        
    # Extract body text (everything after the first blank line)
    parts = content.split('\n\n', 1)
    if len(parts) > 1:
        dashboard_text = parts[1]

# Read the simulated render output
render_output = ""
render_path = os.path.join(wiki_dir, "output", "dashboard_test.txt")
if os.path.exists(render_path):
    with open(render_path, 'r', encoding='utf-8') as f:
        render_output = f.read()

# Check server logs for GUI interaction
gui_save_detected = False
log_path = "/home/ga/tiddlywiki.log"
if os.path.exists(log_path):
    with open(log_path, 'r', encoding='utf-8') as f:
        log_content = f.read()
        if "Dispatching 'save' task: Drug Interaction Finder" in log_content:
            gui_save_detected = True

# Read task start time
start_time = 0
if os.path.exists("/tmp/task_start_time.txt"):
    with open("/tmp/task_start_time.txt", 'r') as f:
        try:
            start_time = float(f.read().strip())
        except ValueError:
            pass

result = {
    "dashboard_exists": dashboard_exists,
    "dashboard_tags": dashboard_tags,
    "dashboard_text": dashboard_text,
    "created_during_task": creation_time >= start_time if start_time > 0 else True,
    "render_output": render_output,
    "gui_save_detected": gui_save_detected
}

with open(result_file, 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2)

PYEOF

echo "Result JSON saved to /tmp/search_app_result.json"
cat /tmp/search_app_result.json

# Cleanup the injected state
rm -f "$WIKI_DIR/tiddlers/\$__temp_drug-search.tid"

echo "=== Export complete ==="