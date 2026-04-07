#!/bin/bash
# Export script for implement_faq_schema_and_rich_snippets task

echo "=== Exporting FAQ Schema task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot as evidence
take_screenshot /tmp/task_final.png

TARGET_POST_ID=$(cat /tmp/target_post_id 2>/dev/null || echo "")
INITIAL_MODIFIED=$(cat /tmp/initial_post_modified 2>/dev/null || echo "")

# Use Python to safely query and export the potentially complex HTML/JSON content
python3 << EOF
import json
import subprocess
import os
import sys

post_id = "$TARGET_POST_ID"
initial_modified = "$INITIAL_MODIFIED"

result_data = {
    "post_found": False,
    "post_id": post_id,
    "initial_modified": initial_modified,
    "current_modified": "",
    "post_content": "",
    "post_excerpt": "",
    "post_modified_during_task": False
}

if post_id:
    try:
        # We query the database container directly to avoid WP-CLI parsing quirks with complex JSON/HTML
        cmd = [
            "docker", "exec", "wordpress-mariadb", "mysql", 
            "-u", "wordpress", "-pwordpresspass", "wordpress", "-N", "-B", 
            "-e", f"SELECT post_content, post_excerpt, post_modified FROM wp_posts WHERE ID={post_id}"
        ]
        db_output = subprocess.check_output(cmd).decode('utf-8').strip()
        
        if db_output:
            parts = db_output.split('\t')
            result_data["post_found"] = True
            result_data["post_content"] = parts[0] if len(parts) > 0 else ""
            result_data["post_excerpt"] = parts[1] if len(parts) > 1 else ""
            result_data["current_modified"] = parts[2] if len(parts) > 2 else ""
            
            if result_data["current_modified"] != initial_modified and result_data["current_modified"] != "":
                result_data["post_modified_during_task"] = True
    except Exception as e:
        print(f"Error querying database: {e}")

# Save to tmp file safely
temp_file = "/tmp/faq_schema_result_temp.json"
final_file = "/tmp/faq_schema_result.json"

with open(temp_file, "w") as f:
    json.dump(result_data, f, indent=2)

os.system(f"sudo mv {temp_file} {final_file}")
os.system(f"sudo chmod 666 {final_file}")
print("Exported JSON results safely.")
EOF

echo ""
echo "Result JSON saved to /tmp/faq_schema_result.json"
echo "=== Export complete ==="