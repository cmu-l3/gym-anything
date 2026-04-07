#!/bin/bash
# Export script for setup_digital_archives task (post_task hook)

echo "=== Exporting setup_digital_archives result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# Extract page data using WP-CLI as JSON (safest way to avoid Bash quoting bugs)
wp post list --post_type=page --post_status=any --format=json \
    --fields=ID,post_title,post_status,post_parent,post_password --allow-root > /tmp/wp_all_pages.json

# Extract content lengths via direct DB query (since content can be huge, we only need the length)
wp db query "SELECT ID, LENGTH(post_content) as content_length FROM wp_posts WHERE post_type='page'" \
    --format=json --allow-root > /tmp/wp_page_lengths.json

# Extract page creation timestamps
wp db query "SELECT ID, UNIX_TIMESTAMP(post_date) as creation_time FROM wp_posts WHERE post_type='page'" \
    --format=json --allow-root > /tmp/wp_page_times.json

# Use Python to merge everything and calculate the delta safely
python3 << 'EOF'
import json
import os

try:
    with open('/tmp/wp_all_pages.json', 'r') as f:
        pages = json.load(f)
except Exception:
    pages = []

try:
    with open('/tmp/wp_page_lengths.json', 'r') as f:
        lengths_raw = json.load(f)
        lengths = {int(p['ID']): int(p['content_length']) for p in lengths_raw}
except Exception:
    lengths = {}

try:
    with open('/tmp/wp_page_times.json', 'r') as f:
        times_raw = json.load(f)
        times = {int(p['ID']): int(p['creation_time']) for p in times_raw}
except Exception:
    times = {}

try:
    with open('/tmp/initial_page_count', 'r') as f:
        initial_count = int(f.read().strip())
except Exception:
    initial_count = 0

try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        start_time = int(f.read().strip())
except Exception:
    start_time = 0

result = {
    "initial_page_count": initial_count,
    "current_page_count": len(pages),
    "task_start_time": start_time,
    "pages": []
}

for p in pages:
    p_id = int(p['ID'])
    p['content_length'] = lengths.get(p_id, 0)
    p['creation_time'] = times.get(p_id, 0)
    p['created_during_task'] = p['creation_time'] >= start_time
    result['pages'].append(p)

with open('/tmp/setup_digital_archives_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Move to final location with permissive rights
sudo chmod 666 /tmp/setup_digital_archives_result.json

echo "Result saved to /tmp/setup_digital_archives_result.json"
echo "=== Export complete ==="