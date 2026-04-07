#!/bin/bash
echo "=== Exporting publish_real_estate_listings_with_meta result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract WordPress data cleanly via Python and WP-CLI to ensure robust JSON generation
python3 << 'EOF'
import json
import subprocess
import os
import time

def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL).decode('utf-8').strip()
    except Exception:
        return ""

result = {
    "timestamp": int(time.time()),
    "category_exists": False,
    "listings": {}
}

# Check category
cat_check = run_cmd("cd /var/www/html/wordpress && wp term get category Properties --field=name --allow-root")
if cat_check.lower() == "properties":
    result["category_exists"] = True

expected_titles = [
    "8424 Bluebonnet Lane, Austin, TX 78758",
    "1904 Ocean Drive, Miami Beach, FL 33139",
    "755 Pinecone Ridge, Denver, CO 80204"
]

meta_keys = ['property_price', 'property_beds', 'property_baths', 'property_sqft', 'property_status']

for title in expected_titles:
    # Try exact title
    post_id = run_cmd(f"cd /var/www/html/wordpress && wp post list --post_type=post --title=\"{title}\" --post_status=publish --field=ID --allow-root")
    
    # If not found, try searching via query in case of minor whitespace differences
    if not post_id:
        post_id = run_cmd(f"cd /var/www/html/wordpress && wp db query \"SELECT ID FROM wp_posts WHERE post_title LIKE '%{title[:20]}%' AND post_status='publish' AND post_type='post' LIMIT 1\" --skip-column-names --allow-root")

    if post_id:
        # Get Categories
        cats_json_str = run_cmd(f"cd /var/www/html/wordpress && wp post term list {post_id} category --fields=name --format=json --allow-root")
        try:
            cats = [c["name"] for c in json.loads(cats_json_str)]
        except:
            cats = []

        # Get comment status
        comment_status = run_cmd(f"cd /var/www/html/wordpress && wp post get {post_id} --field=comment_status --allow-root")
        
        # Get Custom Fields
        meta = {}
        for key in meta_keys:
            meta_val = run_cmd(f"cd /var/www/html/wordpress && wp post meta get {post_id} {key} --allow-root")
            meta[key] = meta_val

        result["listings"][title] = {
            "found": True,
            "id": post_id,
            "categories": cats,
            "comment_status": comment_status,
            "meta": meta
        }
    else:
        result["listings"][title] = {
            "found": False
        }

# Get task start timestamp for anti-gaming verification
try:
    with open('/tmp/task_start_timestamp', 'r') as f:
        result["task_start_timestamp"] = int(f.read().strip())
except:
    result["task_start_timestamp"] = 0

# Save JSON result
temp_file = "/tmp/real_estate_task_result_tmp.json"
final_file = "/tmp/real_estate_task_result.json"

with open(temp_file, "w") as f:
    json.dump(result, f, indent=4)

# Move to final location securely
os.system(f"rm -f {final_file} 2>/dev/null || sudo rm -f {final_file} 2>/dev/null || true")
os.system(f"cp {temp_file} {final_file} 2>/dev/null || sudo cp {temp_file} {final_file}")
os.system(f"chmod 666 {final_file} 2>/dev/null || sudo chmod 666 {final_file} 2>/dev/null || true")
os.system(f"rm -f {temp_file}")
EOF

echo ""
echo "Result JSON saved to /tmp/real_estate_task_result.json"
cat /tmp/real_estate_task_result.json
echo ""
echo "=== Export complete ==="