#!/bin/bash
echo "=== Setting up GDPR Erasure Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure OrientDB is ready
wait_for_orientdb 60

TARGET_EMAIL="john.smith@example.com"
NEW_EMAIL="erased_john_smith@agency.local"

# 1. Reset state: Verify if the "erased" user exists from a previous run and restore them
echo "Checking for previous run artifacts..."
ERASED_COUNT=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM Profiles WHERE Email='$NEW_EMAIL'" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

if [ "$ERASED_COUNT" -gt "0" ]; then
    echo "Found previously erased user. Restoring original..."
    # We delete the erased user and let the reconstruction logic below handle it
    orientdb_sql "demodb" "DELETE VERTEX Profiles WHERE Email='$NEW_EMAIL'" >/dev/null
fi

# 2. Ensure John Smith exists
echo "Ensuring target user '$TARGET_EMAIL' exists..."
orientdb_sql "demodb" "UPDATE Profiles SET Name='John', Surname='Smith', Gender='Male', Birthday='1985-03-15', Nationality='American' WHERE Email='$TARGET_EMAIL'" >/dev/null

# If update didn't match (user doesn't exist), insert him
COUNT=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM Profiles WHERE Email='$TARGET_EMAIL'" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

if [ "$COUNT" -eq "0" ]; then
    echo "Inserting missing user..."
    orientdb_sql "demodb" "INSERT INTO Profiles SET Email='$TARGET_EMAIL', Name='John', Surname='Smith', Gender='Male', Birthday='1985-03-15', Nationality='American'" >/dev/null
fi

# 3. Ensure distinct edges exist (Crucial for verification)
# We need 'HasFriend' edges (to be deleted) and 'HasStayed' edges (to be kept)

# Get RID of John Smith
JOHN_RID=$(orientdb_sql "demodb" "SELECT @rid as rid FROM Profiles WHERE Email='$TARGET_EMAIL'" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('result',[{}])[0].get('rid',''))")
echo "Target RID: $JOHN_RID"

# Ensure at least 2 friends (creating edges to random other profiles)
echo "Seeding 'HasFriend' edges..."
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM $JOHN_RID TO (SELECT FROM Profiles WHERE Email <> '$TARGET_EMAIL' LIMIT 1)" >/dev/null 2>&1
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email <> '$TARGET_EMAIL' SKIP 1 LIMIT 1) TO $JOHN_RID" >/dev/null 2>&1

# Ensure at least 2 stays (creating edges to random hotels)
echo "Seeding 'HasStayed' edges..."
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM $JOHN_RID TO (SELECT FROM Hotels LIMIT 1)" >/dev/null 2>&1
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM $JOHN_RID TO (SELECT FROM Hotels SKIP 1 LIMIT 1)" >/dev/null 2>&1

# 4. Record Initial State for Verification
echo "Recording initial state..."
# Count initial stays to ensure they aren't deleted later
INITIAL_STAYS=$(orientdb_sql "demodb" "SELECT out('HasStayed').size() as cnt FROM Profiles WHERE Email='$TARGET_EMAIL'" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('result',[{}])[0].get('cnt',0))")

echo "$INITIAL_STAYS" > /tmp/initial_stays_count.txt
echo "$JOHN_RID" > /tmp/target_rid.txt
date +%s > /tmp/task_start_time.txt

echo "Initial Stays: $INITIAL_STAYS"

# 5. Launch Firefox to Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="