#!/bin/bash
set -euo pipefail

echo "=== Setup: reconcile_country_hotel_governance ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh
wait_for_orientdb 90

rm -f /tmp/reconcile_country_hotel_governance_result.json \
      /tmp/reconcile_country_hotel_governance_baseline.json \
      /tmp/task_start_timestamp 2>/dev/null || true

sql_count() {
    local query="$1"
    orientdb_sql "demodb" "$query" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0"
}

ensure_country() {
    local name="$1"
    local ctype="$2"
    local cnt
    cnt=$(sql_count "SELECT COUNT(*) as cnt FROM Countries WHERE Name='${name}'")
    if [ "$cnt" = "0" ]; then
        orientdb_sql "demodb" "INSERT INTO Countries SET Name='${name}', Type='${ctype}'" >/dev/null 2>&1 || true
    fi
}

ensure_hotel() {
    local name="$1"
    local htype="$2"
    local phone="$3"
    local lat="$4"
    local lon="$5"
    local street="$6"
    local city="$7"
    local country="$8"
    local stars="$9"

    local cnt
    cnt=$(sql_count "SELECT COUNT(*) as cnt FROM Hotels WHERE Name='${name}'")
    if [ "$cnt" = "0" ]; then
        orientdb_sql "demodb" "INSERT INTO Hotels SET Name='${name}', Type='${htype}', Phone='${phone}', Latitude=${lat}, Longitude=${lon}, Street='${street}', City='${city}', Country='${country}', Stars=${stars}" >/dev/null 2>&1 || true
    fi
}

# Ensure canonical baseline records exist
ensure_country "United Kingdom" "European"
ensure_country "Netherlands" "European"

ensure_hotel "The Savoy" "Luxury" "+44-20-7836-4343" "51.5099" "-0.1201" "Strand" "London" "United Kingdom" "5"
ensure_hotel "Intercontinental Amsterdam" "Luxury" "+31-20-655-6262" "52.3702" "4.9076" "Professor Tulpplein 1" "Amsterdam" "Netherlands" "5"

# Reset previous task artifacts
orientdb_sql "demodb" "DROP CLASS GovernanceFixLog UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX GovernanceFixLog.IssueKey" >/dev/null 2>&1 || true

# Inject governance drift (the task to repair)
orientdb_sql "demodb" "UPDATE Countries SET Type='American' WHERE Name='United Kingdom'" >/dev/null 2>&1 || true
orientdb_sql "demodb" "UPDATE Countries SET Type='Asian' WHERE Name='Netherlands'" >/dev/null 2>&1 || true
orientdb_sql "demodb" "UPDATE Hotels SET Country='UK' WHERE Name='The Savoy'" >/dev/null 2>&1 || true
orientdb_sql "demodb" "UPDATE Hotels SET Country='Holland' WHERE Name='Intercontinental Amsterdam'" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX Countries.Name" >/dev/null 2>&1 || true

# Baseline snapshot
python3 << 'PYEOF'
import json, urllib.request, base64

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

snapshot = {
    "countries": sql("SELECT Name, Type FROM Countries WHERE Name in ['United Kingdom','Netherlands']").get("result", []),
    "hotels": sql("SELECT Name, Country FROM Hotels WHERE Name in ['The Savoy','Intercontinental Amsterdam']").get("result", []),
}
with open('/tmp/reconcile_country_hotel_governance_baseline.json', 'w') as f:
    json.dump(snapshot, f, indent=2)
PYEOF

date +%s > /tmp/task_start_timestamp

kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 8
take_screenshot /tmp/task_start_reconcile_country_hotel_governance.png

echo "=== Setup complete: reconcile_country_hotel_governance ==="
