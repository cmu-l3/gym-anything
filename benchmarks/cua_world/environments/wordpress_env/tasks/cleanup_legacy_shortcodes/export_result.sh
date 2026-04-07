#!/bin/bash
# Export script for cleanup_legacy_shortcodes task

echo "=== Exporting cleanup_legacy_shortcodes result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Function to get post data safely using WP-CLI
get_post_info() {
    local title="$1"
    local post_id=$(wp db query "SELECT ID FROM wp_posts WHERE post_title='$title' AND post_type='post' AND post_status='publish' LIMIT 1" --skip-column-names --allow-root 2>/dev/null)
    
    if [ -n "$post_id" ]; then
        local content=$(wp post get "$post_id" --field=post_content --allow-root 2>/dev/null)
        local modified=$(wp post get "$post_id" --field=post_modified_gmt --allow-root 2>/dev/null)
        local modified_ts=$(date -d "$modified" +%s 2>/dev/null || echo "0")
        
        # Output as delimiter-separated to parse in Python
        echo "FOUND_DELIM${post_id}_DELIM${modified_ts}_DELIM${content}"
    else
        echo "NOT_FOUND"
    fi
}

echo "Retrieving Post 1..."
P1_RAW=$(get_post_info "Service Interruption Notice")

echo "Retrieving Post 2..."
P2_RAW=$(get_post_info "Watch our latest webinar")

echo "Retrieving Post 3..."
P3_RAW=$(get_post_info "Annual Report 2025")

# Use Python to safely construct the JSON result
python3 << EOF
import json
import sys

def parse_raw(raw_str):
    if raw_str.strip() == "NOT_FOUND":
        return {"found": False, "id": None, "modified_ts": 0, "content": ""}
    
    parts = raw_str.replace("FOUND_DELIM", "").split("_DELIM", 2)
    if len(parts) == 3:
        return {
            "found": True, 
            "id": parts[0], 
            "modified_ts": int(parts[1]) if parts[1].isdigit() else 0, 
            "content": parts[2]
        }
    return {"found": False, "id": None, "modified_ts": 0, "content": ""}

p1_data = parse_raw("""$P1_RAW""")
p2_data = parse_raw("""$P2_RAW""")
p3_data = parse_raw("""$P3_RAW""")

task_start = int("$TASK_START") if "$TASK_START".isdigit() else 0

result = {
    "task_start_timestamp": task_start,
    "post1": p1_data,
    "post2": p2_data,
    "post3": p3_data
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)
EOF

chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export complete ==="