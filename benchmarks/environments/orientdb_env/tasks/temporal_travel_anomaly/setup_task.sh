#!/bin/bash
echo "=== Setting up Temporal Travel Anomaly task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running
wait_for_orientdb 120

# 1. Update Schema: Add necessary properties
echo "Updating schema..."
orientdb_sql "demodb" "CREATE PROPERTY HasStayed.CheckIn DATE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE PROPERTY HasStayed.Nights INTEGER" > /dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE PROPERTY Profiles.Suspicious BOOLEAN" > /dev/null 2>&1 || true

# 2. Seed Data with Python script
# This script generates innocent travel history and specific 'teleportation' cases
cat << 'EOF' > /tmp/seed_anomalies.py
import sys
import json
import random
import datetime
import urllib.request
import base64
import os

BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}

def sql(command):
    req = urllib.request.Request(
        f"{BASE_URL}/command/demodb/sql",
        data=json.dumps({"command": command}).encode(),
        headers=HEADERS,
        method="POST"
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except Exception as e:
        # print(f"Error: {e}")
        return {}

# Fetch base data
print("Fetching profiles and hotels...")
profiles_res = sql("SELECT @rid, Email FROM Profiles")
hotels_res = sql("SELECT @rid, City FROM Hotels")

if 'result' not in profiles_res or 'result' not in hotels_res:
    print("Failed to fetch base data")
    sys.exit(1)

profiles = profiles_res['result']
hotels = hotels_res['result']

# Group hotels by city
hotels_by_city = {}
for h in hotels:
    city = h.get('City', 'Unknown')
    if city not in hotels_by_city:
        hotels_by_city[city] = []
    hotels_by_city[city].append(h['@rid'])

cities = list(hotels_by_city.keys())

# Clear existing edges to ensure clean slate for this logic puzzle
print("Clearing existing HasStayed edges...")
sql("DELETE EDGE HasStayed")
sql("UPDATE Profiles SET Suspicious = null")

# Select targets
random.seed(42) # Deterministic for debugging, but still "random" logic
random.shuffle(profiles)

fraudsters = profiles[:3]  # 3 suspicious users
innocents = profiles[3:13] # 10 innocent users with history

suspicious_emails = [p['Email'] for p in fraudsters]

def create_stay(rid, hotel_rid, date_str, nights):
    sql(f"CREATE EDGE HasStayed FROM {rid} TO {hotel_rid} SET CheckIn='{date_str}', Nights={nights}")

# 1. Generate Innocent History
for p in innocents:
    curr_date = datetime.date(2023, 1, 1)
    for _ in range(3):
        city = random.choice(cities)
        hotel = random.choice(hotels_by_city[city])
        nights = random.randint(3, 7)
        create_stay(p['@rid'], hotel, curr_date.strftime("%Y-%m-%d"), nights)
        # Advance time significantly to avoid overlap
        curr_date += datetime.timedelta(days=nights + random.randint(5, 20))

# 2. Generate Fraudsters (Overlapping in diff cities)
# Case A: Direct overlap
f1 = fraudsters[0]
city_a = cities[0]
city_b = cities[1]
h1 = random.choice(hotels_by_city[city_a])
h2 = random.choice(hotels_by_city[city_b])
# Stay 1: Jan 10 - Jan 15
create_stay(f1['@rid'], h1, "2023-01-10", 5) 
# Stay 2: Jan 12 - Jan 14 (Overlap!)
create_stay(f1['@rid'], h2, "2023-01-12", 2)

# Case B: Partial overlap end/start
f2 = fraudsters[1]
city_c = cities[2]
city_d = cities[3]
h3 = random.choice(hotels_by_city[city_c])
h4 = random.choice(hotels_by_city[city_d])
# Stay 1: Feb 1 - Feb 5
create_stay(f2['@rid'], h3, "2023-02-01", 4)
# Stay 2: Feb 4 - Feb 8 (Overlap on Feb 4)
create_stay(f2['@rid'], h4, "2023-02-04", 4)

# Case C: Enveloped
f3 = fraudsters[2]
city_e = cities[4]
city_f = cities[5]
h5 = random.choice(hotels_by_city[city_e])
h6 = random.choice(hotels_by_city[city_f])
# Stay 1: Mar 1 - Mar 20
create_stay(f3['@rid'], h5, "2023-03-01", 19)
# Stay 2: Mar 10 - Mar 12
create_stay(f3['@rid'], h6, "2023-03-10", 2)

# Save ground truth (hidden)
ground_truth_path = "/var/lib/orientdb/ground_truth_anomalies.json"
os.makedirs(os.path.dirname(ground_truth_path), exist_ok=True)
with open(ground_truth_path, "w") as f:
    json.dump(suspicious_emails, f)

print(f"Seeded {len(fraudsters)} anomalies and {len(innocents)} innocent histories.")
EOF

# Run the seeding script
python3 /tmp/seed_anomalies.py

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile \
    'http://localhost:2480/studio/index.html' &"
sleep 8

# Initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="