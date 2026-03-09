#!/bin/bash
set -euo pipefail

echo "=== Setup: backfill_reciprocal_travel_friendships ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh
wait_for_orientdb 90

rm -f /tmp/backfill_reciprocal_travel_friendships_result.json \
      /tmp/backfill_reciprocal_travel_friendships_baseline.json \
      /tmp/task_start_timestamp 2>/dev/null || true

sql_count() {
    local query="$1"
    orientdb_sql "demodb" "$query" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0"
}

ensure_profile() {
    local email="$1" name="$2" surname="$3" gender="$4" bday="$5" nationality="$6"
    local cnt
    cnt=$(sql_count "SELECT COUNT(*) as cnt FROM Profiles WHERE Email='${email}'")
    if [ "$cnt" = "0" ]; then
        orientdb_sql "demodb" "INSERT INTO Profiles SET Email='${email}', Name='${name}', Surname='${surname}', Gender='${gender}', Birthday='${bday}', Nationality='${nationality}'" >/dev/null 2>&1 || true
    fi
}

ensure_hotel() {
    local name="$1" htype="$2" phone="$3" lat="$4" lon="$5" street="$6" city="$7" country="$8" stars="$9"
    local cnt
    cnt=$(sql_count "SELECT COUNT(*) as cnt FROM Hotels WHERE Name='${name}'")
    if [ "$cnt" = "0" ]; then
        orientdb_sql "demodb" "INSERT INTO Hotels SET Name='${name}', Type='${htype}', Phone='${phone}', Latitude=${lat}, Longitude=${lon}, Street='${street}', City='${city}', Country='${country}', Stars=${stars}" >/dev/null 2>&1 || true
    fi
}

# Ensure deterministic cohort entities
ensure_profile "john.smith@example.com" "John" "Smith" "Male" "1985-03-15" "American"
ensure_profile "david.jones@example.com" "David" "Jones" "Male" "1978-11-08" "British"
ensure_profile "emma.white@example.com" "Emma" "White" "Female" "1991-12-19" "British"
ensure_profile "maria.garcia@example.com" "Maria" "Garcia" "Female" "1990-07-22" "Spanish"
ensure_profile "sophie.martin@example.com" "Sophie" "Martin" "Female" "1992-05-30" "French"

ensure_hotel "The Savoy" "Luxury" "+44-20-7836-4343" "51.5099" "-0.1201" "Strand" "London" "United Kingdom" "5"
ensure_hotel "Hotel de Crillon" "Palace" "+33-1-44-71-15-00" "48.8679" "2.3215" "10 Place de la Concorde" "Paris" "France" "5"

# Clean up class from prior attempts
orientdb_sql "demodb" "DELETE EDGE TravelAffinity" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS TravelAffinity UNSAFE" >/dev/null 2>&1 || true

# Normalize HasStayed edges for deterministic shared-hotel cohort logic
for email in john.smith@example.com david.jones@example.com emma.white@example.com maria.garcia@example.com sophie.martin@example.com; do
  orientdb_sql "demodb" "DELETE EDGE HasStayed WHERE out.Email='${email}' AND in.Name IN ['The Savoy','Hotel de Crillon']" >/dev/null 2>&1 || true
done

orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='john.smith@example.com') TO (SELECT FROM Hotels WHERE Name='The Savoy')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='david.jones@example.com') TO (SELECT FROM Hotels WHERE Name='The Savoy')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='emma.white@example.com') TO (SELECT FROM Hotels WHERE Name='The Savoy')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='emma.white@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel de Crillon')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='maria.garcia@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel de Crillon')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='sophie.martin@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel de Crillon')" >/dev/null 2>&1 || true

# Reset HasFriend only in cohort to an asymmetric state
orientdb_sql "demodb" "DELETE EDGE HasFriend WHERE out.Email IN ['john.smith@example.com','david.jones@example.com','emma.white@example.com','maria.garcia@example.com','sophie.martin@example.com'] AND in.Email IN ['john.smith@example.com','david.jones@example.com','emma.white@example.com','maria.garcia@example.com','sophie.martin@example.com']" >/dev/null 2>&1 || true

orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='john.smith@example.com') TO (SELECT FROM Profiles WHERE Email='david.jones@example.com')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='emma.white@example.com') TO (SELECT FROM Profiles WHERE Email='david.jones@example.com')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='maria.garcia@example.com') TO (SELECT FROM Profiles WHERE Email='sophie.martin@example.com')" >/dev/null 2>&1 || true

# Ensure expected reverse edges are absent at start
orientdb_sql "demodb" "DELETE EDGE HasFriend WHERE out.Email='david.jones@example.com' AND in.Email='john.smith@example.com'" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DELETE EDGE HasFriend WHERE out.Email='david.jones@example.com' AND in.Email='emma.white@example.com'" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DELETE EDGE HasFriend WHERE out.Email='sophie.martin@example.com' AND in.Email='maria.garcia@example.com'" >/dev/null 2>&1 || true

# Baseline snapshot for anti-gaming verification
python3 << 'PYEOF'
import json
import urllib.request
import base64

auth = base64.b64encode(b"root:GymAnything123!").decode()
headers = {"Authorization": f"Basic {auth}", "Content-Type": "application/json"}

def sql(cmd):
    req = urllib.request.Request(
        "http://localhost:2480/command/demodb/sql",
        data=json.dumps({"command": cmd}).encode(),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.loads(r.read())
    except Exception:
        return {}

baseline = {
    "reverse_edges": sql(
        "SELECT out.Email as src, in.Email as dst FROM HasFriend WHERE "
        "(out.Email='david.jones@example.com' AND in.Email='john.smith@example.com') OR "
        "(out.Email='david.jones@example.com' AND in.Email='emma.white@example.com') OR "
        "(out.Email='sophie.martin@example.com' AND in.Email='maria.garcia@example.com')"
    ).get("result", []),
    "travel_affinity_count": sql("SELECT COUNT(*) as cnt FROM TravelAffinity").get("result", [{}])[0].get("cnt", 0),
}
with open("/tmp/backfill_reciprocal_travel_friendships_baseline.json", "w", encoding="utf-8") as f:
    json.dump(baseline, f, indent=2)
PYEOF

date +%s > /tmp/task_start_timestamp

kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 8
take_screenshot /tmp/task_start_backfill_reciprocal_travel_friendships.png

echo "=== Setup complete: backfill_reciprocal_travel_friendships ==="
