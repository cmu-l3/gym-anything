#!/bin/bash
set -e
echo "=== Setting up task: normalize_amenities_graph ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running
wait_for_orientdb 120

# 1. Inject Legacy Data (The "Problem" to solve)
# We use a python script to inject the EMBEDDEDLIST data via REST API using standard urllib
echo "Injecting legacy Amenities data..."
python3 -c '
import urllib.request
import json
import base64
import sys

BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Content-Type": "application/json"
}

def sql(db, command):
    data = json.dumps({"command": command}).encode()
    req = urllib.request.Request(
        f"{BASE_URL}/command/{db}/sql",
        data=data,
        headers=HEADERS,
        method="POST"
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status
    except Exception as e:
        print(f"Error executing {command}: {e}")
        return 0

# Create the property
print("Creating Hotels.Amenities property...")
sql("demodb", "CREATE PROPERTY Hotels.Amenities EMBEDDEDLIST STRING")

# Define the data mapping
updates = [
    ("Hotel Artemide",        ["WiFi", "Bar", "Restaurant"]),
    ("Hotel Adlon Kempinski", ["WiFi", "Gym", "Spa", "Concierge"]),
    ("Hotel de Crillon",      ["WiFi", "Bar", "Spa", "Valet"]),
    ("The Savoy",             ["WiFi", "Restaurant", "Concierge"]),
    ("The Plaza Hotel",       ["WiFi", "Gym", "Spa", "Concierge"]),
    ("Park Hyatt Tokyo",      ["WiFi", "Pool", "Gym", "Bar"]),
    ("Copacabana Palace",     ["Pool", "Bar"])
]

# Apply updates
count = 0
for hotel, amenities in updates:
    amenities_str = json.dumps(amenities)
    cmd = f"UPDATE Hotels SET Amenities = {amenities_str} WHERE Name = \"{hotel}\""
    status = sql("demodb", cmd)
    if status == 200:
        count += 1

print(f"Updated {count} hotels with legacy amenity data.")
'

# 2. Launch Firefox to Studio
echo "Launching Firefox..."
kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 10

# 3. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="