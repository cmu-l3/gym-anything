#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up embedded_document_enrichment task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB
wait_for_orientdb 120

# Verify demodb exists and Hotels class has data
HOTEL_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
echo "Hotels count: $HOTEL_COUNT"

if [ "$HOTEL_COUNT" -lt 5 ]; then
    echo "ERROR: Not enough hotels in demodb ($HOTEL_COUNT). Running seeder..."
    python3 /workspace/scripts/seed_demodb.py 2>&1 | tail -5
fi

# Verify the 5 specific hotels exist
echo "Verifying target hotels..."
for HOTEL_NAME in "Hotel Artemide" "Hotel Adlon Kempinski" "The Savoy" "Park Hyatt Tokyo" "Copacabana Palace"; do
    FOUND=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels WHERE Name='${HOTEL_NAME}'" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
    if [ "$FOUND" = "0" ]; then
        echo "  ERROR: Hotel '${HOTEL_NAME}' not found! Re-seeding required."
        python3 /workspace/scripts/seed_demodb.py
        break
    fi
done

# CLEAN STATE: Remove Amenities/SocialMedia properties if they exist
echo "Cleaning schema..."
orientdb_sql "demodb" "DROP PROPERTY Hotels.Amenities IF EXISTS FORCE" 2>/dev/null || true
orientdb_sql "demodb" "DROP PROPERTY Hotels.SocialMedia IF EXISTS FORCE" 2>/dev/null || true

# Remove any pre-existing report file
rm -f /home/ga/Documents/hotels_with_pool.json

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Ensure Firefox is open to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 5

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="