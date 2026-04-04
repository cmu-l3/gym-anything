#!/bin/bash
echo "=== Exporting Refactor VIP Migration Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create a Python script to query the database state and export as JSON
# We use Python here because bash/curl/jq parsing of complex JSON is fragile
cat > /tmp/inspect_db.py << 'EOF'
import urllib.request
import json
import base64
import sys

ROOT_PASS = "GymAnything123!"
BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(f"root:{ROOT_PASS}".encode()).decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Content-Type": "application/json"
}

def sql(command):
    try:
        data = json.dumps({"command": command}).encode()
        req = urllib.request.Request(
            f"{BASE_URL}/command/demodb/sql",
            data=data,
            headers=HEADERS,
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e), "result": []}

def get_class_info(class_name):
    try:
        req = urllib.request.Request(
            f"{BASE_URL}/database/demodb",
            headers=HEADERS,
            method="GET"
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
            for cls in data.get("classes", []):
                if cls["name"] == class_name:
                    return cls
            return None
    except Exception:
        return None

results = {}

# 1. Check Schema
results['class_vip_exists'] = get_class_info('VIPProfiles') is not None
results['class_managers_exists'] = get_class_info('Managers') is not None
results['class_managedby_exists'] = get_class_info('ManagedBy') is not None

vip_cls = get_class_info('VIPProfiles')
if vip_cls:
    results['vip_superclass'] = vip_cls.get('superClass', '') or vip_cls.get('superClasses', [])

managers_cls = get_class_info('Managers')
if managers_cls:
    results['managers_superclass'] = managers_cls.get('superClass', '') or managers_cls.get('superClasses', [])

# 2. Check Migration (Source)
# Count profiles that are still strictly 'Profiles' class but are Japanese
res_source = sql("SELECT count(*) FROM Profiles WHERE Nationality='Japanese' AND @class='Profiles'")
results['remaining_source_count'] = res_source.get('result', [{}])[0].get('count', -1)

# 3. Check Migration (Target)
res_target = sql("SELECT count(*) FROM VIPProfiles WHERE Nationality='Japanese'")
results['vip_count'] = res_target.get('result', [{}])[0].get('count', -1)

# 4. Check Edge Preservation
# Get a VIP profile and check its edges (e.g., HasFriend)
# We look for Yuki Tanaka
res_yuki = sql("SELECT * FROM VIPProfiles WHERE Email='yuki.tanaka@example.com'")
if res_yuki.get('result'):
    yuki = res_yuki['result'][0]
    results['yuki_found_in_vip'] = True
    
    # Check for presence of edge fields (starts with out_ or in_)
    edges = [k for k in yuki.keys() if (k.startswith('out_') or k.startswith('in_')) and k != 'out_ManagedBy']
    results['yuki_preserved_edges_count'] = len(edges)
    results['yuki_preserved_edges_list'] = edges
else:
    results['yuki_found_in_vip'] = False
    results['yuki_preserved_edges_count'] = 0

# 5. Check Manager Linking
res_manager = sql("SELECT @rid FROM Managers WHERE Name='Akira Kurosawa'")
if res_manager.get('result'):
    manager_rid = res_manager['result'][0].get('@rid')
    results['manager_found'] = True
    results['manager_rid'] = manager_rid
    
    # Verify links
    # Check if VIPs have out_ManagedBy pointing to manager
    res_links = sql(f"SELECT count(*) FROM VIPProfiles WHERE out_ManagedBy CONTAINS {manager_rid}")
    results['linked_vip_count'] = res_links.get('result', [{}])[0].get('count', -1)
else:
    results['manager_found'] = False
    results['linked_vip_count'] = 0

# Save
with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)
EOF

# Run the inspection script
python3 /tmp/inspect_db.py

echo "Result generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="