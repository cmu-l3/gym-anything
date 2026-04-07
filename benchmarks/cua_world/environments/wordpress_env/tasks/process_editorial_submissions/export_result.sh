#!/bin/bash
echo "=== Exporting process_editorial_submissions result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve the IDs created in setup
if [ ! -f /tmp/task_post_ids.json ]; then
    echo "ERROR: /tmp/task_post_ids.json not found."
    exit 1
fi

# We use an inline Python script to query WordPress and format the JSON securely
# This avoids massive escaping headaches in bash
python3 << 'EOF'
import json
import subprocess
import os

def run_wp(cmd):
    # Run wp-cli command and return stdout
    res = subprocess.run(
        f"wp {cmd} --allow-root --path=/var/www/html/wordpress", 
        shell=True, 
        capture_output=True, 
        text=True
    )
    return res.stdout.strip()

with open('/tmp/task_post_ids.json', 'r') as f:
    ids = json.load(f)

# Evaluate Spam post
spam_status = run_wp(f"post get {ids['spam_id']} --field=post_status")
if not spam_status:
    spam_status = "deleted"

# Evaluator for articles
def get_details(pid):
    status = run_wp(f"post get {pid} --field=post_status")
    content = run_wp(f"post get {pid} --field=post_content")
    
    # Get categories as JSON array
    cats_json = run_wp(f"post term list {pid} category --fields=name --format=json")
    try:
        cat_list = [c['name'] for c in json.loads(cats_json)] if cats_json else []
    except json.JSONDecodeError:
        cat_list = []
        
    # Get thumbnail filename
    thumb_id = run_wp(f"post meta get {pid} _thumbnail_id")
    thumb_file = ""
    if thumb_id and thumb_id.isdigit():
        attached_file = run_wp(f"post meta get {thumb_id} _wp_attached_file")
        if attached_file:
            thumb_file = attached_file.split('/')[-1]

    # Convert content to lower case to check for the editor note flexibly
    content_lower = content.lower()
    has_note = "[editor:" in content_lower
    
    return {
        "status": status,
        "has_note": has_note,
        "content_length": len(content),
        "categories": cat_list,
        "thumb_file": thumb_file
    }

output = {
    "spam_status": spam_status,
    "art1": get_details(ids['art1_id']),
    "art2": get_details(ids['art2_id']),
    "timestamp": run_wp("eval 'echo date(\"c\");'")
}

with open('/tmp/process_editorial_submissions_result.json', 'w') as f:
    json.dump(output, f, indent=2)

EOF

# Fix permissions so the framework can read it
chmod 666 /tmp/process_editorial_submissions_result.json

echo "Result saved to /tmp/process_editorial_submissions_result.json"
cat /tmp/process_editorial_submissions_result.json
echo "=== Export complete ==="