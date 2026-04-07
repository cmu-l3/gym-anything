#!/bin/bash
# Export script for moderate_comments task
# Exports all comment data safely to a JSON file for the verifier

echo "=== Exporting moderate_comments result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# Export all comments in JSON format via WP-CLI (safest parsing method)
# --status=all includes approved, pending, spam, and trash
wp comment list --status=all --format=json --allow-root > /tmp/all_comments_raw.json 2>/dev/null

# Get the saved ID of Sarah's comment to check for replies
SARAH_ID=$(cat /tmp/sarah_comment_id 2>/dev/null || echo "0")
START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# Use Python to package everything cleanly into a final JSON file
python3 << 'EOF'
import json
import os
import sys

try:
    with open('/tmp/all_comments_raw.json', 'r') as f:
        comments_data = json.load(f)
except Exception as e:
    print(f"Error loading raw comments: {e}")
    comments_data = []

sarah_id = os.environ.get('SARAH_ID', '0')
start_time = int(os.environ.get('START_TIME', '0'))
end_time = int(os.environ.get('END_TIME', '0'))

result = {
    'comments': comments_data,
    'sarah_comment_id': sarah_id,
    'task_start_time': start_time,
    'task_end_time': end_time,
    'task_duration_sec': max(0, end_time - start_time)
}

# Write final result file with global read permissions
out_path = '/tmp/moderate_comments_result.json'
with open(out_path, 'w') as f:
    json.dump(result, f, indent=2)
os.chmod(out_path, 0o666)
print(f"Result exported successfully to {out_path}")
EOF

echo "=== Export complete ==="