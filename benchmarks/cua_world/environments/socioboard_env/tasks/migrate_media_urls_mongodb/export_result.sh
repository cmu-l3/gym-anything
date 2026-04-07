#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to safely query MongoDB and calculate scoring metrics
python3 << 'PYEOF'
import json
import subprocess
import os

def get_docs(collection):
    try:
        # Export collection as JSON string
        res = subprocess.run(
            ["mongosh", "socioboard", "--quiet", "--eval", f"JSON.stringify(db.{collection}.find().toArray())"],
            capture_output=True, text=True
        )
        return json.loads(res.stdout)
    except Exception as e:
        print(f"Error querying {collection}: {e}")
        return []

posts = get_docs("userpublishposts")
drafts = get_docs("drafts")
all_docs = posts + drafts

legacy_domain = "http://media.acmesocial.legacy"
new_domain = "https://cdn.acme-corp.com"

# 1. Count domains
legacy_count = sum(1 for d in all_docs if legacy_domain in str(d.get("mediaUrl", "")))
new_count = sum(1 for d in all_docs if new_domain in str(d.get("mediaUrl", "")))

# 2. Check path preservation (sample checks of the unique paths injected during setup)
path1_preserved = any(new_domain + "/campaigns/summer/sale_banner_v2.jpg" == str(d.get("mediaUrl", "")) for d in posts)
path2_preserved = any(new_domain + "/seasonal/halloween/spooky_sale.png" == str(d.get("mediaUrl", "")) for d in drafts)

# 3. Detect hardcoded wipe (agent just replaced the whole string without keeping the path)
hardcoded_overwrite = False
if new_count > 0:
    hardcoded_overwrite = all(str(d.get("mediaUrl", "")) == new_domain for d in all_docs if new_domain in str(d.get("mediaUrl", "")))

# 4. Check control URLs (YouTube, Vimeo, Imgur must remain untouched)
control1_preserved = any("https://www.youtube.com/watch?v=dQw4w9WgXcQ" == str(d.get("mediaUrl", "")) for d in posts)
control2_preserved = any("https://vimeo.com/123456789" == str(d.get("mediaUrl", "")) for d in drafts)

# Load initial state
initial_legacy = 5
try:
    with open("/tmp/initial_state.json", "r") as f:
        initial_state = json.load(f)
        initial_legacy = initial_state.get("total_legacy", 5)
except Exception:
    pass

result = {
    "task_start": int('$TASK_START'),
    "task_end": int('$TASK_END'),
    "legacy_count_final": legacy_count,
    "new_count_final": new_count,
    "initial_legacy": initial_legacy,
    "path1_preserved": path1_preserved,
    "path2_preserved": path2_preserved,
    "hardcoded_overwrite": hardcoded_overwrite,
    "control1_preserved": control1_preserved,
    "control2_preserved": control2_preserved,
    "screenshot_exists": os.path.exists("/tmp/task_final.png")
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Exported MongoDB evaluation results:"
cat /tmp/task_result.json

echo "=== Export complete ==="