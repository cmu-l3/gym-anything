#!/bin/bash
set -euo pipefail

echo "=== Setup: remediate_swapped_geocoordinates ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh
wait_for_orientdb 90

rm -f /tmp/remediate_swapped_geocoordinates_result.json \
      /tmp/remediate_swapped_geocoordinates_baseline.json \
      /tmp/task_start_timestamp 2>/dev/null || true

sql_count() {
    local query="$1"
    orientdb_sql "demodb" "$query" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0"
}

ensure_hotel() {
    local name="$1" htype="$2" phone="$3" lat="$4" lon="$5" street="$6" city="$7" country="$8" stars="$9"
    local cnt
    cnt=$(sql_count "SELECT COUNT(*) as cnt FROM Hotels WHERE Name='${name}'")
    if [ "$cnt" = "0" ]; then
        orientdb_sql "demodb" "INSERT INTO Hotels SET Name='${name}', Type='${htype}', Phone='${phone}', Latitude=${lat}, Longitude=${lon}, Street='${street}', City='${city}', Country='${country}', Stars=${stars}" >/dev/null 2>&1 || true
    fi
}

ensure_hotel "The Plaza Hotel" "Historic" "+1-212-759-3000" "40.7645" "-73.9744" "768 Fifth Avenue" "New York" "United States" "5"
ensure_hotel "Park Hyatt Tokyo" "Luxury" "+81-3-5322-1234" "35.6858" "139.6909" "3-7-1-2 Nishi Shinjuku" "Tokyo" "Japan" "5"
ensure_hotel "Four Seasons Sydney" "Luxury" "+61-2-9250-3100" "-33.8611" "151.2112" "199 George Street" "Sydney" "Australia" "5"

# Remove old audit artifacts
orientdb_sql "demodb" "DELETE VERTEX GeoFixAudit" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS GeoFixAudit UNSAFE" >/dev/null 2>&1 || true

# Inject swapped coordinate corruption
orientdb_sql "demodb" "UPDATE Hotels SET Latitude=-73.9744, Longitude=40.7645 WHERE Name='The Plaza Hotel'" >/dev/null 2>&1 || true
orientdb_sql "demodb" "UPDATE Hotels SET Latitude=139.6909, Longitude=35.6858 WHERE Name='Park Hyatt Tokyo'" >/dev/null 2>&1 || true
orientdb_sql "demodb" "UPDATE Hotels SET Latitude=151.2112, Longitude=-33.8611 WHERE Name='Four Seasons Sydney'" >/dev/null 2>&1 || true

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
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read())

rows = sql("SELECT Name, Latitude, Longitude FROM Hotels WHERE Name IN ['The Plaza Hotel','Park Hyatt Tokyo','Four Seasons Sydney']").get("result", [])
coords = {
    r.get("Name"): {
        "Latitude": float(r.get("Latitude", 0.0)),
        "Longitude": float(r.get("Longitude", 0.0)),
    }
    for r in rows
    if r.get("Name")
}
with open("/tmp/remediate_swapped_geocoordinates_baseline.json", "w", encoding="utf-8") as f:
    json.dump({"coordinates": coords}, f, indent=2)
PYEOF

date +%s > /tmp/task_start_timestamp

kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 8
take_screenshot /tmp/task_start_remediate_swapped_geocoordinates.png

echo "=== Setup complete: remediate_swapped_geocoordinates ==="
