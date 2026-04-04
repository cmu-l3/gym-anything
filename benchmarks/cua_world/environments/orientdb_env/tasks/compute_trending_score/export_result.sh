#!/bin/bash
echo "=== Exporting compute_trending_score results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create a Python script to extract the database state for verification
# We need:
# 1. The Schema of Hotels class (to verify property existence)
# 2. The Data: Hotel Name, TrendingScore, and the list of linked Reviews (Date, Stars)
#    to verify the calculation logic off-line.

cat > /tmp/extract_data.py << 'EOF'
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

def sql_command(command):
    try:
        data = json.dumps({"command": command}).encode()
        req = urllib.request.Request(
            f"{BASE_URL}/command/demodb/sql",
            data=data,
            headers=HEADERS,
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

def sql_query(query):
    try:
        # URL encode the query
        q_enc = urllib.parse.quote(query)
        req = urllib.request.Request(
            f"{BASE_URL}/query/demodb/sql/{q_enc}/1000",
            headers=HEADERS,
            method="GET"
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

def get_class_schema(class_name):
    try:
        req = urllib.request.Request(
            f"{BASE_URL}/database/demodb",
            headers=HEADERS,
            method="GET"
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            db_info = json.loads(resp.read())
            classes = db_info.get("classes", [])
            for c in classes:
                if c["name"] == class_name:
                    return c
            return None
    except Exception as e:
        return None

result_data = {
    "schema_correct": False,
    "property_type": None,
    "hotels_data": []
}

# 1. Check Schema
hotels_schema = get_class_schema("Hotels")
if hotels_schema:
    props = {p["name"]: p for p in hotels_schema.get("properties", [])}
    if "TrendingScore" in props:
        result_data["schema_correct"] = True
        result_data["property_type"] = props["TrendingScore"].get("type")

# 2. Extract Data for Logic Verification
# We fetch Hotels and traverse to their Reviews to get the raw data for verification
# Query: Fetch Hotel Name, TrendingScore, and the list of Reviews with Date and Stars
# Using a fetchplan to expand the 'out_HasReview' edge would be ideal, but raw query logic is safer here.

query = "SELECT Name, TrendingScore, out('HasReview') as Reviews FROM Hotels"
raw_hotels = sql_query(query)

if "result" in raw_hotels:
    for h in raw_hotels["result"]:
        hotel_entry = {
            "name": h.get("Name"),
            "trending_score": h.get("TrendingScore"),
            "reviews": []
        }
        
        # OrientDB returns links (RIDs) for the Reviews field in the initial query
        # unless we used a fetch plan. To be robust without relying on complex REST fetch plans,
        # we will fetch the review details if they are just RIDs.
        # Actually, let's just do a cleaner query that projects the data we want.
        
        # Optimized Query:
        # SELECT Name, TrendingScore, out('HasReview').Include('Date', 'Stars') as ReviewDetails FROM Hotels
        # However, nested projections in OrientDB SQL can be tricky across versions.
        # Let's try to get the raw RIDs and assume the verification logic (in verify.py) 
        # is too hard if we export everything.
        # BETTER STRATEGY: Do the logic check for a few hotels inside THIS script 
        # or export enough data. Let's export the review data structure.
        
        # We will iterate and fetch review details for each hotel. This might be slow if DB is huge,
        # but for DemoDB it is fine (approx 10-20 hotels).
        
        review_rids = h.get("Reviews", [])
        if review_rids:
             # Sanitize RIDs
            if isinstance(review_rids, list):
                # Fetch details for these RIDs
                # Convert list of RIDs to string for IN clause: [#12:0, #12:1]
                rids_str = "[" + ",".join([f"{rid}" for rid in review_rids if isinstance(rid, str)]) + "]"
                if len(review_rids) > 0:
                    reviews_q = f"SELECT Date, Stars FROM Reviews WHERE @rid IN {rids_str}"
                    reviews_res = sql_command(reviews_q)
                    if "result" in reviews_res:
                         hotel_entry["reviews"] = reviews_res["result"]
        
        result_data["hotels_data"].append(hotel_entry)

with open("/tmp/verification_data.json", "w") as f:
    json.dump(result_data, f, indent=2)

EOF

# Execute the python script
python3 /tmp/extract_data.py

# Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_data": $(cat /tmp/verification_data.json 2>/dev/null || echo "{}")
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Data saved to /tmp/task_result.json"