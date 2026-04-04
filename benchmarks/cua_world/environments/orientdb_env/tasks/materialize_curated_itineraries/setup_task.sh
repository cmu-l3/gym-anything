#!/bin/bash
set -euo pipefail

echo "=== Setup: materialize_curated_itineraries ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh
wait_for_orientdb 90

rm -f /tmp/materialize_curated_itineraries_result.json \
      /tmp/materialize_curated_itineraries_baseline.json \
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

ensure_restaurant() {
    local name="$1" rtype="$2" phone="$3" lat="$4" lon="$5" street="$6" city="$7" country="$8"
    local cnt
    cnt=$(sql_count "SELECT COUNT(*) as cnt FROM Restaurants WHERE Name='${name}'")
    if [ "$cnt" = "0" ]; then
        orientdb_sql "demodb" "INSERT INTO Restaurants SET Name='${name}', Type='${rtype}', Phone='${phone}', Latitude=${lat}, Longitude=${lon}, Street='${street}', City='${city}', Country='${country}'" >/dev/null 2>&1 || true
    fi
}

ensure_monument() {
    local name="$1" mtype="$2" lat="$3" lon="$4" street="$5" city="$6" country="$7"
    local cnt
    cnt=$(sql_count "SELECT COUNT(*) as cnt FROM Monuments WHERE Name='${name}'")
    if [ "$cnt" = "0" ]; then
        orientdb_sql "demodb" "INSERT INTO Monuments SET Name='${name}', Type='${mtype}', Latitude=${lat}, Longitude=${lon}, Street='${street}', City='${city}', Country='${country}'" >/dev/null 2>&1 || true
    fi
}

ensure_profile "sophie.martin@example.com" "Sophie" "Martin" "Female" "1992-05-30" "French"
ensure_profile "luca.rossi@example.com" "Luca" "Rossi" "Male" "1988-01-17" "Italian"
ensure_profile "elena.petrakis@example.com" "Elena" "Petrakis" "Female" "1993-10-28" "Greek"

ensure_hotel "Hotel de Crillon" "Palace" "+33-1-44-71-15-00" "48.8679" "2.3215" "10 Place de la Concorde" "Paris" "France" "5"
ensure_hotel "Hotel Artemide" "Boutique" "+39-06-4884-6000" "41.8981" "12.4989" "Via Nazionale 22" "Rome" "Italy" "4"
ensure_hotel "Grande Bretagne Hotel" "Historic" "+30-210-333-0000" "37.9754" "23.7367" "Syntagma Square 1" "Athens" "Greece" "5"

ensure_restaurant "Le Cinq" "French Gastronomic" "+33-1-49-52-71-54" "48.8728" "2.3091" "31 Avenue George V" "Paris" "France"
ensure_restaurant "Da Enzo al 29" "Traditional Italian" "+39-06-581-2260" "41.8902" "12.4672" "Via dei Vascellari 29" "Rome" "Italy"
ensure_restaurant "Spondi" "French Mediterranean" "+30-210-756-4021" "37.9781" "23.7467" "Pyrronos 5" "Athens" "Greece"

ensure_monument "Eiffel Tower" "Iron Lattice Tower" "48.8584" "2.2945" "Champ de Mars 5" "Paris" "France"
ensure_monument "Colosseum" "Ancient Amphitheatre" "41.8902" "12.4922" "Piazza del Colosseo 1" "Rome" "Italy"
ensure_monument "Parthenon" "Ancient Temple" "37.9715" "23.7257" "Acropolis Hill" "Athens" "Greece"

# Remove previous task artifacts
orientdb_sql "demodb" "DELETE VERTEX ItinerarySummary" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS ItinerarySummary UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX ItinerarySummary.Email" >/dev/null 2>&1 || true

# Deterministic edge state for cohort
for email in sophie.martin@example.com luca.rossi@example.com elena.petrakis@example.com; do
  orientdb_sql "demodb" "DELETE EDGE HasStayed WHERE out.Email='${email}'" >/dev/null 2>&1 || true
  orientdb_sql "demodb" "DELETE EDGE HasEaten WHERE out.Email='${email}'" >/dev/null 2>&1 || true
  orientdb_sql "demodb" "DELETE EDGE HasVisited WHERE out.Email='${email}'" >/dev/null 2>&1 || true
done

orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='sophie.martin@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel de Crillon')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='luca.rossi@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Artemide')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='elena.petrakis@example.com') TO (SELECT FROM Hotels WHERE Name='Grande Bretagne Hotel')" >/dev/null 2>&1 || true

orientdb_sql "demodb" "CREATE EDGE HasEaten FROM (SELECT FROM Profiles WHERE Email='sophie.martin@example.com') TO (SELECT FROM Restaurants WHERE Name='Le Cinq')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasEaten FROM (SELECT FROM Profiles WHERE Email='luca.rossi@example.com') TO (SELECT FROM Restaurants WHERE Name='Da Enzo al 29')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasEaten FROM (SELECT FROM Profiles WHERE Email='elena.petrakis@example.com') TO (SELECT FROM Restaurants WHERE Name='Spondi')" >/dev/null 2>&1 || true

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

visits = sql(
    "SELECT COUNT(*) as cnt FROM HasVisited WHERE out.Email IN "
    "['sophie.martin@example.com','luca.rossi@example.com','elena.petrakis@example.com']"
).get("result", [{}])[0].get("cnt", 0)

summary_rows = sql("SELECT COUNT(*) as cnt FROM ItinerarySummary").get("result", [{}])[0].get("cnt", 0)

with open("/tmp/materialize_curated_itineraries_baseline.json", "w", encoding="utf-8") as f:
    json.dump(
        {
            "visit_count": int(visits or 0),
            "summary_row_count": int(summary_rows or 0),
        },
        f,
        indent=2,
    )
PYEOF

date +%s > /tmp/task_start_timestamp

kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 8
take_screenshot /tmp/task_start_materialize_curated_itineraries.png

echo "=== Setup complete: materialize_curated_itineraries ==="
