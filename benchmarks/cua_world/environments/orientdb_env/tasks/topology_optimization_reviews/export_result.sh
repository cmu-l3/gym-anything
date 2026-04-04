#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting topology_optimization_reviews results ==="

# Record task end timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare to query OrientDB for validation data
RESULT_JSON="/tmp/task_result.json"

# Python script to gather verification data
cat > /tmp/gather_validation.py << 'EOF'
import json
import sys
import requests
import base64
import os

BASE_URL = "http://localhost:2480"
AUTH_STR = "root:GymAnything123!"
AUTH_B64 = base64.b64encode(AUTH_STR.encode()).decode()
HEADERS = {
    "Authorization": f"Basic {AUTH_B64}",
    "Content-Type": "application/json"
}

def sql(command):
    try:
        resp = requests.post(f"{BASE_URL}/command/demodb/sql", json={"command": command}, headers=HEADERS)
        if resp.status_code == 200:
            return resp.json().get('result', [])
        return []
    except:
        return []

def get_schema():
    try:
        resp = requests.get(f"{BASE_URL}/database/demodb", headers=HEADERS)
        if resp.status_code == 200:
            return resp.json().get('classes', [])
        return []
    except:
        return []

# 1. Get Schema Info (Check if PostedReview exists and what properties it has)
schema = get_schema()
posted_review_class = next((c for c in schema if c['name'] == 'PostedReview'), None)
reviews_class = next((c for c in schema if c['name'] == 'Reviews'), None)
made_review_class = next((c for c in schema if c['name'] == 'MadeReview'), None)
has_review_class = next((c for c in schema if c['name'] == 'HasReview'), None)

properties = []
if posted_review_class:
    properties = [p['name'] for p in posted_review_class.get('properties', [])]

# 2. Count PostedReview Edges
edge_count_res = sql("SELECT count(*) as c FROM PostedReview")
edge_count = edge_count_res[0]['c'] if edge_count_res else 0

# 3. Count Old Vertices (for Cleanup verification)
old_vertex_count = 0
if reviews_class:
    old_res = sql("SELECT count(*) as c FROM Reviews")
    old_vertex_count = old_res[0]['c'] if old_res else 0
else:
    # If class doesn't exist, count is effectively 0
    old_vertex_count = 0

# 4. Spot Check Data Integrity
# Looking for John Smith -> Hotel Artemide with Rating=4
# Note: In OrientDB, we need to match the profile and hotel to find the edge
spot_check_query = """
    SELECT Rating, Comment, ReviewDate 
    FROM PostedReview 
    WHERE out.Name = 'John' AND out.Surname = 'Smith' 
    AND in.Name = 'Hotel Artemide'
"""
spot_res = sql(spot_check_query)
spot_check_data = spot_res[0] if spot_res else {}

# 5. Get initial count from file
try:
    with open("/tmp/initial_review_count.txt", "r") as f:
        initial_count = int(f.read().strip())
except:
    initial_count = 0

output = {
    "schema": {
        "PostedReview_exists": bool(posted_review_class),
        "properties": properties,
        "Reviews_class_exists": bool(reviews_class),
        "MadeReview_class_exists": bool(made_review_class),
        "HasReview_class_exists": bool(has_review_class)
    },
    "counts": {
        "initial_reviews": initial_count,
        "final_edges": edge_count,
        "remaining_old_vertices": old_vertex_count
    },
    "spot_check": spot_check_data,
    "timestamp": os.popen("date +%s").read().strip()
}

print(json.dumps(output))
EOF

# Run validation gatherer
python3 /tmp/gather_validation.py > "$RESULT_JSON"

# Fix permissions
chmod 666 "$RESULT_JSON"

echo "Result data exported to $RESULT_JSON"
echo "=== Export complete ==="