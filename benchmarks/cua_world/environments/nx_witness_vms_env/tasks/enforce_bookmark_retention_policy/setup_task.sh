#!/bin/bash
set -e
echo "=== Setting up enforce_bookmark_retention_policy task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Firefox is ready (agent might use it for docs or verification)
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/system"

# ==============================================================================
# 1. AUTHENTICATION & PREPARATION
# ==============================================================================
refresh_nx_token > /dev/null 2>&1 || true
TOKEN=$(get_nx_token)

if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to obtain auth token"
    exit 1
fi

# Get a valid camera ID to attach bookmarks to
CAMERA_ID=$(get_first_camera_id)
if [ -z "$CAMERA_ID" ]; then
    echo "ERROR: No cameras found. Cannot create bookmarks."
    exit 1
fi
echo "Using Camera ID: $CAMERA_ID"

# ==============================================================================
# 2. CLEAR EXISTING BOOKMARKS
# ==============================================================================
echo "Clearing existing bookmarks..."
EXISTING_IDS=$(curl -sk "${NX_BASE}/rest/v1/bookmarks" -H "Authorization: Bearer ${TOKEN}" | \
    python3 -c "import sys,json; print(' '.join([b['id'] for b in json.load(sys.stdin)]))" 2>/dev/null || true)

for bid in $EXISTING_IDS; do
    curl -sk -X DELETE "${NX_BASE}/rest/v1/bookmarks/${bid}" -H "Authorization: Bearer ${TOKEN}" >/dev/null
done

# ==============================================================================
# 3. GENERATE SCENARIO DATA (Using Python for reliable date math)
# ==============================================================================
echo "Generating scenario bookmarks..."

# Create a python script to generate bookmarks via API
cat > /tmp/generate_bookmarks.py << PY_EOF
import sys
import time
import json
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

base_url = "${NX_BASE}"
token = "${TOKEN}"
camera_id = "${CAMERA_ID}"

headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json"
}

# Current time in ms
now_ms = int(time.time() * 1000)
day_ms = 24 * 60 * 60 * 1000

# Scenarios: (Age in Days, Description, Should be Deleted?)
scenarios = [
    (40, "Regular old event", True),                # Old, No Hold -> DELETE
    (50, "Another old event", True),                # Old, No Hold -> DELETE
    (45, "Evidence Case 101 LegalHold", False),     # Old, Hold -> KEEP
    (60, "Important legalhold check", False),       # Old, Hold (lowercase) -> KEEP
    (10, "Recent shift change", False),             # New, No Hold -> KEEP
    (5,  "Recent incident LegalHold", False),       # New, Hold -> KEEP
    (90, "Very old trash footage", True),           # Old, No Hold -> DELETE
    (15, "Just a test", False)                      # New, No Hold -> KEEP
]

created_bookmarks = []

print(f"Current Time MS: {now_ms}")

for age_days, desc, should_delete in scenarios:
    # Calculate start time
    start_time = now_ms - (age_days * day_ms)
    
    payload = {
        "deviceId": camera_id,
        "name": f"Task Bookmark {age_days}d",
        "description": desc,
        "startTimeMs": start_time,
        "durationMs": 30000, # 30 seconds
        "tags": ["task_gen"]
    }
    
    try:
        r = requests.post(f"{base_url}/rest/v1/bookmarks", json=payload, headers=headers, verify=False, timeout=10)
        if r.status_code in [200, 201]:
            resp_data = r.json()
            # Handle list response (sometimes returns list of 1) or dict
            if isinstance(resp_data, list) and len(resp_data) > 0:
                b_id = resp_data[0].get('id')
            else:
                b_id = resp_data.get('id')
                
            print(f"Created: {b_id} | Age: {age_days}d | Desc: {desc} | Delete? {should_delete}")
            
            created_bookmarks.append({
                "id": b_id,
                "age_days": age_days,
                "description": desc,
                "expected_deleted": should_delete,
                "start_time_ms": start_time
            })
        else:
            print(f"Failed to create bookmark: {r.status_code} {r.text}")
    except Exception as e:
        print(f"Error: {e}")

# Save ground truth for verifier
with open('/tmp/bookmark_ground_truth.json', 'w') as f:
    json.dump(created_bookmarks, f, indent=2)

PY_EOF

# Execute the generator
python3 /tmp/generate_bookmarks.py

# Take screenshot of browser (optional, but good practice)
maximize_firefox
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="