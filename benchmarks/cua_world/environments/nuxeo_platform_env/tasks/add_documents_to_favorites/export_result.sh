#!/bin/bash
# Export results for add_documents_to_favorites
# Queries API to check if documents are in Favorites collection

echo "=== Exporting results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Python script to robustly query API and check collections
cat << 'EOF' > /tmp/check_favorites.py
import requests
import json
import sys
import time

AUTH = ('Administrator', 'Administrator')
BASE_URL = 'http://localhost:8080/nuxeo/api/v1'

def get_doc_collections(path):
    """Get collection IDs for a document"""
    url = f"{BASE_URL}/path{path}"
    headers = {'Content-Type': 'application/json', 'X-NXproperties': 'dublincore,collectionMember'}
    try:
        r = requests.get(url, auth=AUTH, headers=headers)
        if r.status_code == 200:
            data = r.json()
            return data.get('properties', {}).get('collectionMember:collectionIds', [])
        return []
    except Exception as e:
        return []

def get_collection_title(uid):
    """Get title of a collection by UID"""
    url = f"{BASE_URL}/id/{uid}"
    headers = {'X-NXproperties': 'dublincore'}
    try:
        r = requests.get(url, auth=AUTH, headers=headers)
        if r.status_code == 200:
            return r.json().get('properties', {}).get('dc:title', '')
        return ""
    except:
        return ""

results = {
    "annual_report": {"in_favorites": False, "collections": []},
    "contract_template": {"in_favorites": False, "collections": []}
}

# Check Annual Report
ar_cols = get_doc_collections("/default-domain/workspaces/Projects/Annual-Report-2023")
for uid in ar_cols:
    title = get_collection_title(uid)
    results["annual_report"]["collections"].append(title)
    if "Favorite" in title:  # Matches "Favorites"
        results["annual_report"]["in_favorites"] = True

# Check Contract Template
ct_cols = get_doc_collections("/default-domain/workspaces/Templates/Contract-Template")
for uid in ct_cols:
    title = get_collection_title(uid)
    results["contract_template"]["collections"].append(title)
    if "Favorite" in title:
        results["contract_template"]["in_favorites"] = True

# Add timestamps
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        start_time = int(f.read().strip())
    results['task_start_time'] = start_time
except:
    results['task_start_time'] = 0

print(json.dumps(results, indent=2))
EOF

# Run python script and save output
python3 /tmp/check_favorites.py > /tmp/api_check.json

# Combine into final result
cat << EOF > /tmp/task_result.json
{
    "api_check": $(cat /tmp/api_check.json),
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": $(date +%s)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json