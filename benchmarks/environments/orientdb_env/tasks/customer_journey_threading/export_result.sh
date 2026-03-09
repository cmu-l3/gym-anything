#!/bin/bash
echo "=== Exporting Customer Journey Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python script to deeply inspect the graph structure
# We need to verify the linked list structure: Profile -> Event1 -> Event2 -> Event3 -> Event4
echo "Analyzing graph structure..."
python3 -c '
import sys
import json
import base64
import urllib.request
import traceback

BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}
TARGET_EMAIL = "sofia.ricci@journey.com"

def sql_cmd(cmd):
    try:
        req = urllib.request.Request(f"{BASE_URL}/command/demodb/sql", data=json.dumps({"command": cmd}).encode(), headers=HEADERS, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

def sql_query(query):
    try:
        # URL encode query
        q = urllib.parse.quote(query)
        req = urllib.request.Request(f"{BASE_URL}/query/demodb/sql/{q}/20", headers=HEADERS, method="GET")
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

result = {
    "schema_exists": False,
    "profile_found": False,
    "starts_journey_edge_exists": False,
    "total_events_count": 0,
    "chain_length": 0,
    "chain_dates": [],
    "chain_sorted": False,
    "errors": []
}

try:
    # 1. Check Schema
    db_info = sql_cmd("SELECT count(*) FROM (SELECT expand(classes) FROM metadata:schema) WHERE name IN [\"TimelineEvent\", \"NextEvent\", \"StartsJourney\"]")
    schema_count = db_info.get("result", [{}])[0].get("count", 0)
    result["schema_exists"] = (schema_count >= 3)
    
    if not result["schema_exists"]:
        result["errors"].append(f"Missing classes. Found count: {schema_count}")

    # 2. Get Profile
    profile_res = sql_query(f"SELECT @rid FROM Profiles WHERE Email=\"{TARGET_EMAIL}\"")
    profiles = profile_res.get("result", [])
    
    if profiles:
        result["profile_found"] = True
        p_rid = profiles[0].get("@rid")
        
        # 3. Check StartsJourney Edge
        # Query: Select outgoing StartsJourney edges from Profile
        starts_res = sql_query(f"SELECT expand(out(\"StartsJourney\")) FROM {p_rid}")
        start_events = starts_res.get("result", [])
        
        if start_events:
            result["starts_journey_edge_exists"] = True
            current_event = start_events[0]
            
            # 4. Traverse the chain via NextEvent
            chain_dates = []
            visited = set()
            
            while current_event:
                rid = current_event.get("@rid")
                if rid in visited:
                    result["errors"].append("Cycle detected in timeline chain")
                    break
                visited.add(rid)
                
                # Get date
                evt_date = current_event.get("EventDate")
                chain_dates.append(str(evt_date))
                
                # Get next event
                next_res = sql_query(f"SELECT expand(out(\"NextEvent\")) FROM {rid}")
                next_events = next_res.get("result", [])
                
                if next_events:
                    current_event = next_events[0] # Assuming linear chain
                else:
                    current_event = None
            
            result["chain_length"] = len(chain_dates)
            result["chain_dates"] = chain_dates
            
            # Check sort order
            # Dates in OrientDB often come back as strings or timestamps, standardizing on string comparison (YYYY-MM-DD)
            # We filter out None just in case
            valid_dates = [d for d in chain_dates if d]
            if valid_dates and valid_dates == sorted(valid_dates):
                result["chain_sorted"] = True
            
        else:
            result["errors"].append("No StartsJourney edge found from profile")
    else:
        result["errors"].append("Target profile not found")

    # 5. Count total events created (should be 4)
    if result["schema_exists"]:
        cnt_res = sql_cmd("SELECT count(*) FROM TimelineEvent")
        result["total_events_count"] = cnt_res.get("result", [{}])[0].get("count", 0)

except Exception as e:
    result["errors"].append(f"Script exception: {str(e)}")
    traceback.print_exc()

# Save result
with open("/tmp/analysis_result.json", "w") as f:
    json.dump(result, f, indent=2)
'

# Combine python analysis with shell metadata
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "analysis": $(cat /tmp/analysis_result.json 2>/dev/null || echo "{}")
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="