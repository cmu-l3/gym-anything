#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

echo "Rendering required HTML files via TiddlyWiki CLI..."
su - ga -c "cd /home/ga/mywiki && tiddlywiki --rendertiddler 'v18.2.0' 'v18.2.0.html' text/html" > /dev/null 2>&1 || true
su - ga -c "cd /home/ga/mywiki && tiddlywiki --rendertiddler 'GettingStarted' 'GettingStarted.html' text/html" > /dev/null 2>&1 || true

# Use Python to safely parse files and generate the JSON payload
python3 << 'EOF'
import json
import os

def get_file_content(path):
    if os.path.exists(path):
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            return f.read()
    return ""

def get_field(content, field):
    for line in content.split('\n'):
        if line.lower().startswith(field.lower() + ':'):
            return line.split(':', 1)[1].strip()
    return ""

def get_text(content):
    parts = content.split('\n\n', 1)
    return parts[1] if len(parts) > 1 else ""

result = {}

# Check Template
template_path = "/home/ga/mywiki/tiddlers/ReleaseNotesTemplate.tid"
if os.path.exists(template_path):
    content = get_file_content(template_path)
    result['template_exists'] = True
    result['template_tags'] = get_field(content, 'tags')
else:
    result['template_exists'] = False

# Check Release Tiddler
release_path = "/home/ga/mywiki/tiddlers/v18.2.0.tid"
if os.path.exists(release_path):
    content = get_file_content(release_path)
    result['release_exists'] = True
    result['release_tags'] = get_field(content, 'tags')
    result['release_text'] = get_text(content)
else:
    result['release_exists'] = False

# Get rendered HTML (to check if template fired correctly)
result['v18_html'] = get_file_content("/home/ga/mywiki/output/v18.2.0.html")
result['getting_started_html'] = get_file_content("/home/ga/mywiki/output/GettingStarted.html")

# Check log for GUI saves (anti-gaming to ensure they used the browser)
log = get_file_content("/home/ga/tiddlywiki.log")
result['gui_save_detected'] = "Dispatching 'save' task:" in log

# Create the result file
with open('/tmp/task_result.json', 'w', encoding='utf-8') as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
EOF

chmod 666 /tmp/task_result.json

echo "Result JSON saved."
cat /tmp/task_result.json
echo "=== Export complete ==="