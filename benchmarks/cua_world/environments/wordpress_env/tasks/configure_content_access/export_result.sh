#!/bin/bash
# Export script for configure_content_access task
echo "=== Exporting configure_content_access task results ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_final.png

# We use an embedded Python script to safely query WP-CLI JSON output
# This completely avoids complex bash escaping issues for post_content
cat << 'PYTHONEOF' > /tmp/export_wp_data.py
import json
import subprocess
import os

result = {
    "initial_max_id": 0,
    "items": {}
}

try:
    with open('/tmp/task_initial_max_id.txt', 'r') as f:
        result['initial_max_id'] = int(f.read().strip() or '0')
except Exception:
    pass

def get_all_posts(post_type):
    cmd = f"cd /var/www/html/wordpress && wp post list --post_type={post_type} --post_status=any --fields=ID,post_title,post_status,post_password,post_date,post_content --format=json --allow-root"
    try:
        output = subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL).strip()
        if output:
            return json.loads(output)
    except Exception as e:
        print(f"Error fetching {post_type}: {e}")
    return []

all_pages = get_all_posts('page')
all_posts = get_all_posts('post')

def find_item(items, title_fragment):
    for item in items:
        # Check against clean title (WordPress automatically adds prefixes like 'Private: ' to post_title in UI, but usually not DB unless typed manually)
        clean_title = item['post_title'].replace('Private: ', '').replace('Protected: ', '').strip()
        if title_fragment.lower() in clean_title.lower():
            # Convert ID to int for comparison
            item['ID'] = int(item['ID'])
            return item
    return None

result['items']['staff_portal'] = find_item(all_pages, "Staff Resources Portal")
result['items']['getting_started'] = find_item(all_posts, "Getting Started with WordPress")
result['items']['plugins'] = find_item(all_posts, "10 Essential WordPress Plugins")
result['items']['policy'] = find_item(all_pages, "Collection Development Policy")
result['items']['accessing'] = find_item(all_pages, "Accessing Restricted Resources")

with open('/tmp/configure_content_access_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYTHONEOF

# Execute Python script
python3 /tmp/export_wp_data.py

# Ensure permissions
chmod 666 /tmp/configure_content_access_result.json
echo "Results exported successfully:"
cat /tmp/configure_content_access_result.json
echo ""
echo "=== Export complete ==="