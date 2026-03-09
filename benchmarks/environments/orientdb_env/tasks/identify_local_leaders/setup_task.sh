#!/bin/bash
echo "=== Setting up identify_local_leaders task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running
wait_for_orientdb 120

# ------------------------------------------------------------------
# TOPOLOGY INJECTION
# We create a specific graph structure to test the agent's logic deterministicly.
# ------------------------------------------------------------------

echo "Configuring social graph topology..."

# 1. Clean up existing friendship edges to start fresh
orientdb_sql "demodb" "DELETE EDGE HasFriend" > /dev/null

# 2. Define Groups

# GROUP A: The Star (Hub & Spoke)
# Center: John Smith (3 friends)
# Leaves: Maria, David, Sophie (0 friends outgoing in this cluster)
# Expected Result: John is a Local Leader (3 > 0). Leaves are not.
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='john.smith@example.com') TO (SELECT FROM Profiles WHERE Email='maria.garcia@example.com')" > /dev/null
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='john.smith@example.com') TO (SELECT FROM Profiles WHERE Email='david.jones@example.com')" > /dev/null
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='john.smith@example.com') TO (SELECT FROM Profiles WHERE Email='sophie.martin@example.com')" > /dev/null

# GROUP B: The Chain
# Luca (1) -> Anna (1) -> Yuki (0)
# Luca connects to Anna. Anna connects to Yuki.
# Luca: FriendCount=1. Friend Anna has 1. 1 > 1 is False. Luca is NOT leader.
# Anna: FriendCount=1. Friend Yuki has 0. 1 > 0 is True. Anna IS leader.
# Yuki: FriendCount=0. Not leader.
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='luca.rossi@example.com') TO (SELECT FROM Profiles WHERE Email='anna.mueller@example.com')" > /dev/null
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='anna.mueller@example.com') TO (SELECT FROM Profiles WHERE Email='yuki.tanaka@example.com')" > /dev/null

# GROUP C: The Clique (Tie)
# James (1) <-> Emma (1)
# James connects to Emma. Emma connects to James.
# James: FriendCount=1. Friend Emma has 1. 1 > 1 False.
# Emma: FriendCount=1. Friend James has 1. 1 > 1 False.
# Neither is leader.
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='james.brown@example.com') TO (SELECT FROM Profiles WHERE Email='emma.white@example.com')" > /dev/null
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='emma.white@example.com') TO (SELECT FROM Profiles WHERE Email='james.brown@example.com')" > /dev/null

# Remove any properties if they exist from previous runs (to force schema change)
orientdb_sql "demodb" "UPDATE Profiles REMOVE FriendCount, IsLocalLeader" > /dev/null
orientdb_sql "demodb" "DROP PROPERTY Profiles.FriendCount F ORCE" 2>/dev/null || true
orientdb_sql "demodb" "DROP PROPERTY Profiles.IsLocalLeader FORCE" 2>/dev/null || true

echo "Topology injection complete."

# ------------------------------------------------------------------
# UI Setup
# ------------------------------------------------------------------

# Launch Firefox to OrientDB Studio Schema Page
echo "Launching Firefox..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile 'http://localhost:2480/studio/index.html#/database/demodb/schema' &"
sleep 8

# Maximize
WID=$(DISPLAY=:1 wmctrl -l | grep "Mozilla Firefox" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="