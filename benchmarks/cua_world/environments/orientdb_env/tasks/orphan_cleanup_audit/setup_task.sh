#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up orphan_cleanup_audit task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 120

# --- Insert orphan Profiles (no edges) ---
echo "Inserting orphan profiles..."
ORPHAN_PROFILES_DATA=(
    "Email='margaret.chen@tempmail.org', Name='Margaret', Surname='Chen', Gender='Female', Birthday='1986-04-11', Nationality='Canadian'"
    "Email='robert.williams@oldmail.net', Name='Robert', Surname='Williams', Gender='Male', Birthday='1974-09-23', Nationality='American'"
    "Email='aisha.rahman@defunct.co', Name='Aisha', Surname='Rahman', Gender='Female', Birthday='1992-01-07', Nationality='Bangladeshi'"
    "Email='peter.novak@closed.org', Name='Peter', Surname='Novak', Gender='Male', Birthday='1981-06-18', Nationality='Czech'"
    "Email='sarah.murphy@expired.net', Name='Sarah', Surname='Murphy', Gender='Female', Birthday='1988-12-02', Nationality='Irish'"
    "Email='liu.wei@inactive.cn', Name='Liu', Surname='Wei', Gender='Male', Birthday='1995-03-29', Nationality='Chinese'"
    "Email='fatima.ali@removed.org', Name='Fatima', Surname='Ali', Gender='Female', Birthday='1990-08-15', Nationality='Egyptian'"
    "Email='dmitri.volkov@gone.ru', Name='Dmitri', Surname='Volkov', Gender='Male', Birthday='1977-11-30', Nationality='Russian'"
)

for pdata in "${ORPHAN_PROFILES_DATA[@]}"; do
    # Use allow_fail=true in case re-running setup and they exist
    orientdb_sql "demodb" "INSERT INTO Profiles SET ${pdata}" > /dev/null 2>&1 || true
done
echo "  Inserted ${#ORPHAN_PROFILES_DATA[@]} orphan profiles"

# --- Insert orphan Hotels (no edges) ---
echo "Inserting orphan hotels..."
ORPHAN_HOTELS_DATA=(
    "Name='Albergo Cesari', Type='Boutique', Phone='+39-06-6749-701', Latitude=41.8986, Longitude=12.4769, Street='Via di Pietra 89a', City='Rome', Country='Italy', Stars=3"
    "Name='Pousada do Porto Freixo', Type='Historic', Phone='+351-225-310-500', Latitude=41.1453, Longitude=-8.5858, Street='Estrada Nacional 108', City='Porto', Country='Portugal', Stars=4"
    "Name='Ryokan Shimizu', Type='Traditional', Phone='+81-75-561-8200', Latitude=35.0006, Longitude=135.7806, Street='Gojo-sagaru Higashi', City='Kyoto', Country='Japan', Stars=3"
    "Name='Hotel Neri', Type='Boutique', Phone='+39-055-210-895', Latitude=43.7713, Longitude=11.2535, Street='Via de Benci 5', City='Florence', Country='Italy', Stars=4"
)

for hdata in "${ORPHAN_HOTELS_DATA[@]}"; do
    orientdb_sql "demodb" "INSERT INTO Hotels SET ${hdata}" > /dev/null 2>&1 || true
done
echo "  Inserted ${#ORPHAN_HOTELS_DATA[@]} orphan hotels"

# --- Record initial connected counts (for anti-gaming verification) ---
echo "Recording initial connected counts..."

# Count profiles that HAVE edges (should NOT be deleted)
CONNECTED_PROFILES=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Profiles WHERE bothE().size() > 0" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# Count hotels that HAVE edges (should NOT be deleted)
CONNECTED_HOTELS=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels WHERE bothE().size() > 0" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# Save to hidden file
cat > /tmp/initial_connected_counts.txt << EOF
CONNECTED_PROFILES=${CONNECTED_PROFILES}
CONNECTED_HOTELS=${CONNECTED_HOTELS}
EOF
chmod 600 /tmp/initial_connected_counts.txt

echo "  Initial State Recorded: ${CONNECTED_PROFILES} connected profiles, ${CONNECTED_HOTELS} connected hotels"

# --- Ensure Firefox is at Studio ---
echo "Setting up Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 3

# Maximize and focus Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="