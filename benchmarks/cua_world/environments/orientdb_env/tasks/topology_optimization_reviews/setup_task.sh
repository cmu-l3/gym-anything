#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up topology_optimization_reviews task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running
wait_for_orientdb 180

# Run the standard seeder first to ensure base data (Profiles, Hotels)
if ! orientdb_db_exists "demodb"; then
    echo "Creating demodb..."
    /workspace/scripts/seed_demodb.py > /dev/null
fi

# Create a python script to seed specific Review data for this task
# We need known data points to verify the migration
cat > /tmp/seed_reviews.py << 'EOF'
import sys
import json
import random
import requests
import base64

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
        return resp.json()
    except Exception as e:
        print(f"Error executing SQL: {e}")
        return {}

print("Seeding Reviews for Refactoring Task...")

# 1. Clean up potential previous state (for idempotency)
# We want to start with Vertices, so delete any new Edges from previous runs
sql("DELETE EDGE PostedReview")
sql("DROP CLASS PostedReview")

# Ensure old schema exists
sql("CREATE CLASS Reviews EXTENDS V")
sql("CREATE PROPERTY Reviews.Stars INTEGER")
sql("CREATE PROPERTY Reviews.Text STRING")
sql("CREATE PROPERTY Reviews.Date DATE")
sql("CREATE CLASS MadeReview EXTENDS E")
sql("CREATE CLASS HasReview EXTENDS E")

# Clear old reviews to ensure clean counts
sql("DELETE VERTEX Reviews")

# 2. Get some Profiles and Hotels
profiles = sql("SELECT @rid, Name, Surname FROM Profiles LIMIT 10")['result']
hotels = sql("SELECT @rid, Name FROM Hotels LIMIT 10")['result']

if len(profiles) < 3 or len(hotels) < 3:
    print("Not enough profiles/hotels to seed reviews")
    sys.exit(1)

# 3. Create Reviews
# Format: (ProfileIndex, HotelIndex, Stars, Text, Date)
reviews_data = [
    (0, 0, 4, "Great location, small room", "2023-01-15"), # John -> Hotel Artemide
    (0, 1, 5, "Absolutely luxurious", "2023-02-20"),       # John -> Hotel Adlon
    (1, 0, 3, "Noisy street", "2023-03-10"),               # Maria -> Hotel Artemide
    (2, 2, 5, "Best service ever", "2023-04-05"),          # David -> Hotel de Crillon
    (3, 3, 2, "Overpriced", "2023-05-12"),                 # Sophie -> The Savoy
]

count = 0
for p_idx, h_idx, stars, text, date in reviews_data:
    if p_idx < len(profiles) and h_idx < len(hotels):
        prof = profiles[p_idx]
        hot = hotels[h_idx]
        
        # Create Review Vertex
        r = sql(f"INSERT INTO Reviews SET Stars={stars}, Text='{text}', Date='{date}'")
        if 'result' in r and len(r['result']) > 0:
            rev_rid = r['result'][0]['@rid']
            
            # Link Profile -> Review
            sql(f"CREATE EDGE MadeReview FROM {prof['@rid']} TO {rev_rid}")
            
            # Link Review -> Hotel
            sql(f"CREATE EDGE HasReview FROM {rev_rid} TO {hot['@rid']}")
            count += 1

print(f"Seeded {count} specific reviews.")
EOF

# Execute the seeder
python3 /tmp/seed_reviews.py

# Record initial count of Reviews vertices
INITIAL_REVIEWS=$(curl -s -u "root:GymAnything123!" -X POST \
    "http://localhost:2480/command/demodb/sql" \
    -d '{"command":"SELECT count(*) as c FROM Reviews"}' \
    -H "Content-Type: application/json" | \
    python3 -c "import sys, json; print(json.load(sys.stdin)['result'][0]['c'])" 2>/dev/null || echo "0")

echo "$INITIAL_REVIEWS" > /tmp/initial_review_count.txt
echo "Initial Reviews Count: $INITIAL_REVIEWS"

# Setup Firefox
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="