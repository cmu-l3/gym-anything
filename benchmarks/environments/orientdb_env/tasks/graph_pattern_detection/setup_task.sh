#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up graph_pattern_detection task ==="
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running and ready
wait_for_orientdb 120

# 1. Clean Slate: Remove existing TravelBuddy class and HasStayed edges
echo "Cleaning up schema and data..."
orientdb_sql "demodb" "DELETE EDGE TravelBuddy" 2>/dev/null || true
orientdb_sql "demodb" "DROP CLASS TravelBuddy UNSAFE" 2>/dev/null || true
orientdb_sql "demodb" "DELETE EDGE HasStayed" 2>/dev/null || true

# Ensure HasStayed class exists
orientdb_sql "demodb" "CREATE CLASS HasStayed EXTENDS E" 2>/dev/null || true

# 2. Seed Deterministic Data
# We rely on the profiles and hotels already existing in DemoDB (from environment setup)
# We will create specific edges to form a known graph topology.

echo "Seeding deterministic HasStayed edges..."

# Function to safely create an edge
create_stay() {
    local email="$1"
    local hotel="$2"
    # Use standard SQL to create edge between looked-up vertices
    orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='${email}') TO (SELECT FROM Hotels WHERE Name='${hotel}')" > /dev/null
}

# John Smith (3 hotels)
create_stay "john.smith@example.com" "Hotel Artemide"
create_stay "john.smith@example.com" "Hotel Adlon Kempinski"
create_stay "john.smith@example.com" "Hotel de Crillon"

# Maria Garcia (2 hotels)
create_stay "maria.garcia@example.com" "Hotel Artemide"
create_stay "maria.garcia@example.com" "The Savoy"

# David Jones (3 hotels)
create_stay "david.jones@example.com" "Hotel Adlon Kempinski"
create_stay "david.jones@example.com" "Hotel de Crillon"
create_stay "david.jones@example.com" "The Savoy"

# Sophie Martin (2 hotels)
create_stay "sophie.martin@example.com" "Hotel de Crillon"
create_stay "sophie.martin@example.com" "The Savoy"

# Luca Rossi (2 hotels)
create_stay "luca.rossi@example.com" "Hotel Artemide"
create_stay "luca.rossi@example.com" "Hotel Adlon Kempinski"

# Anna Mueller (2 hotels)
create_stay "anna.mueller@example.com" "Hotel Adlon Kempinski"
create_stay "anna.mueller@example.com" "The Savoy"

# Verify setup data
STAY_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM HasStayed" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
echo "Seeded ${STAY_COUNT} HasStayed edges."

# 3. Setup Browser
echo "Launching Firefox to OrientDB Studio..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# 4. Initial Evidence
# Remove any old report file
rm -f /home/ga/travel_buddy_report.txt

take_screenshot /tmp/task_initial.png
echo "Initial screenshot captured."

echo "=== Setup complete ==="