#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Friendship Symmetry Repair Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running
wait_for_orientdb 120

# Step 1: Delete ALL existing HasFriend edges to ensure known starting state
echo "Clearing existing HasFriend edges..."
orientdb_sql "demodb" "DELETE EDGE HasFriend" || true
sleep 1

# Step 2: Create specific HasFriend edges with known asymmetries
echo "Creating HasFriend edges with deliberate asymmetries..."

# Asymmetric pair 1: John Smith -> Maria Garcia (NO reverse)
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='john.smith@example.com') TO (SELECT FROM Profiles WHERE Email='maria.garcia@example.com')"

# Asymmetric pair 2: David Jones -> Sophie Martin (NO reverse)
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='david.jones@example.com') TO (SELECT FROM Profiles WHERE Email='sophie.martin@example.com')"

# Symmetric pair 1: Luca Rossi <-> Anna Mueller (Control group)
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='luca.rossi@example.com') TO (SELECT FROM Profiles WHERE Email='anna.mueller@example.com')"
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='anna.mueller@example.com') TO (SELECT FROM Profiles WHERE Email='luca.rossi@example.com')"

# Asymmetric pair 3: Yuki Tanaka -> James Brown (NO reverse)
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='yuki.tanaka@example.com') TO (SELECT FROM Profiles WHERE Email='james.brown@example.com')"

# Symmetric pair 2: Emma White <-> Carlos Lopez (Control group)
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='emma.white@example.com') TO (SELECT FROM Profiles WHERE Email='carlos.lopez@example.com')"
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='carlos.lopez@example.com') TO (SELECT FROM Profiles WHERE Email='emma.white@example.com')"

sleep 2

# Step 3: Record initial state for verification
INITIAL_COUNT_JSON=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM HasFriend")
INITIAL_COUNT=$(echo "$INITIAL_COUNT_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial HasFriend edge count: $INITIAL_COUNT"

# Step 4: Launch Firefox to OrientDB Studio
echo "Launching Firefox to OrientDB Studio..."
launch_firefox "http://localhost:2480/studio/index.html" 8

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="