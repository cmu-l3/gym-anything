#!/bin/bash
set -e
echo "=== Exporting reify_stay_relationship result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png

# Run Python script to inspect database state
# We do this inside the container to access localhost:2480 easily
python3 -c '
import requests, json, sys, os

AUTH = ("root", "GymAnything123!")
BASE_URL = "http://localhost:2480"
HEADERS = {"Content-Type": "application/json"}

def sql(cmd):
    try:
        resp = requests.post(f"{BASE_URL}/command/demodb/sql", json={"command": cmd}, auth=AUTH, headers=HEADERS)
        if resp.status_code != 200:
            return []
        return resp.json().get("result", [])
    except:
        return []

def get_class_list():
    try:
        resp = requests.get(f"{BASE_URL}/database/demodb", auth=AUTH)
        if resp.status_code != 200:
            return []
        return [c["name"] for c in resp.json().get("classes", [])]
    except:
        return []

# 1. Get Schema Info
classes = get_class_list()
schema_check = {
    "StaySession": "StaySession" in classes,
    "HasSession": "HasSession" in classes,
    "SessionAt": "SessionAt" in classes,
    "HasStayed": "HasStayed" in classes
}

# 2. Get Counts
counts = {}
for cls in ["StaySession", "HasSession", "SessionAt", "HasStayed"]:
    if cls in classes:
        res = sql(f"SELECT count(*) as c FROM {cls}")
        counts[cls] = res[0].get("c", 0) if res else 0
    else:
        counts[cls] = -1  # Indicates class missing

# 3. Connectivity Check (Topology Validation)
# Verify path: Profile -> HasSession -> StaySession -> SessionAt -> Hotel
connectivity_valid = False
path_sample = None

if counts.get("StaySession", 0) > 0:
    # Get a random StaySession
    sessions = sql("SELECT @rid, in(\"HasSession\") as p, out(\"SessionAt\") as h FROM StaySession LIMIT 5")
    valid_paths = 0
    for s in sessions:
        # Check if it has incoming Profile and outgoing Hotel
        has_profile = len(s.get("p", [])) > 0
        has_hotel = len(s.get("h", [])) > 0
        if has_profile and has_hotel:
            valid_paths += 1
            if path_sample is None:
                path_sample = s
    
    if valid_paths > 0:
        connectivity_valid = True

# 4. Load Initial State
initial_count = 0
try:
    with open("/tmp/initial_state.json", "r") as f:
        init_data = json.load(f)
        initial_count = init_data.get("initial_has_stayed_count", 0)
except:
    pass

result = {
    "schema": schema_check,
    "counts": counts,
    "initial_count": initial_count,
    "connectivity_valid": connectivity_valid,
    "path_sample": path_sample
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export finished.")
'

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="