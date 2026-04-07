#!/bin/bash
echo "=== Exporting add_live_chat_widget result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to securely analyze the application state and export JSON
python3 << 'PYEOF'
import os
import sys
import json
import urllib.request
import urllib.error

# Load task start time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        task_start = float(f.read().strip())
except Exception:
    task_start = 0.0

app_dir = '/opt/socioboard/socioboard-web-php'
views_dir = os.path.join(app_dir, 'resources/views')
expected_marker = "window.HelpDesk.widgetId = 'SB-99887766';"

result = {
    'http_status': 0,
    'widget_in_response': False,
    'modified_files': [],
    'proper_placement': False,
    'fatal_error': False
}

# 1. Check Live HTTP Application Response
try:
    req = urllib.request.Request('http://localhost/', headers={'User-Agent': 'Mozilla/5.0'})
    response = urllib.request.urlopen(req, timeout=10)
    result['http_status'] = response.getcode()
    html = response.read().decode('utf-8', errors='ignore')
    if expected_marker in html:
        result['widget_in_response'] = True
except urllib.error.HTTPError as e:
    result['http_status'] = e.code
    result['fatal_error'] = (e.code >= 500)
    html = e.read().decode('utf-8', errors='ignore')
    if expected_marker in html:
        result['widget_in_response'] = True
except Exception as e:
    result['fatal_error'] = True

# 2. Check File Modifications and Placement
modified_files = []
proper_placement = False

for root, dirs, files in os.walk(views_dir):
    for f in files:
        if f.endswith('.blade.php'):
            path = os.path.join(root, f)
            try:
                mtime = os.path.getmtime(path)
                if mtime > task_start:
                    modified_files.append(path)
                    # Check placement
                    with open(path, 'r', encoding='utf-8', errors='ignore') as file_in:
                        content = file_in.read()
                        if expected_marker in content:
                            snip_idx = content.rfind(expected_marker)
                            body_idx = content.find('</body>', snip_idx)
                            # If </body> exists after the snippet, it's placed correctly before it
                            if body_idx != -1:
                                proper_placement = True
            except Exception:
                pass

result['modified_files'] = modified_files
result['proper_placement'] = proper_placement

# Save result JSON
temp_path = '/tmp/result_temp.json'
with open(temp_path, 'w') as f:
    json.dump(result, f, indent=2)

os.system(f"sudo cp {temp_path} /tmp/task_result.json")
os.system("sudo chmod 666 /tmp/task_result.json")
os.system(f"rm {temp_path}")
PYEOF

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="