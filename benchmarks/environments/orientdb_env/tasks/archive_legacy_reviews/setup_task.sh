#!/bin/bash
echo "=== Setting up Archive Legacy Reviews task ==="

# Ensure safe PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 120

# --- DATA PREPARATION ---
# 1. Reset state: Drop 'ArchivedReviews' class if it exists
echo "Cleaning up previous runs..."
orientdb_sql "demodb" "DROP CLASS ArchivedReviews UNSAFE" > /dev/null 2>&1 || true

# 2. Ensure we have known legacy data to archive.
# We will insert specific test records to guarantee the task is solvable and verifiable.
# These will be dated before 2015.
echo "Seeding legacy review data..."

# Helper to get RID of a hotel and a profile
HOTEL_RID=$(orientdb_sql "demodb" "SELECT @rid FROM Hotels LIMIT 1" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['result'][0]['@rid'])")
PROFILE_RID=$(orientdb_sql "demodb" "SELECT @rid FROM Profiles LIMIT 1" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['result'][0]['@rid'])")

if [ -n "$HOTEL_RID" ] && [ -n "$PROFILE_RID" ]; then
    # Insert Legacy Review 1 (2014)
    orientdb_sql "demodb" "CREATE VERTEX Reviews SET Stars=3, Text='Legacy Review 1', Date='2014-05-20'" > /dev/null
    REV1_RID=$(orientdb_sql "demodb" "SELECT @rid FROM Reviews WHERE Text='Legacy Review 1'" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['result'][0]['@rid'])")
    
    # Link Review 1
    orientdb_sql "demodb" "CREATE EDGE MadeReview FROM $PROFILE_RID TO $REV1_RID" > /dev/null
    orientdb_sql "demodb" "CREATE EDGE HasReview FROM $HOTEL_RID TO $REV1_RID" > /dev/null
    
    # Insert Legacy Review 2 (2010)
    orientdb_sql "demodb" "CREATE VERTEX Reviews SET Stars=5, Text='Legacy Review 2', Date='2010-01-01'" > /dev/null
    REV2_RID=$(orientdb_sql "demodb" "SELECT @rid FROM Reviews WHERE Text='Legacy Review 2'" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['result'][0]['@rid'])")
    
    # Link Review 2
    orientdb_sql "demodb" "CREATE EDGE MadeReview FROM $PROFILE_RID TO $REV2_RID" > /dev/null
    orientdb_sql "demodb" "CREATE EDGE HasReview FROM $HOTEL_RID TO $REV2_RID" > /dev/null
    
    echo "Seeded 2 verifiable legacy reviews connected to $HOTEL_RID and $PROFILE_RID"
else
    echo "WARNING: Could not find Hotel or Profile to seed data. Task validation might be less precise."
fi

# --- STATE RECORDING ---
# Count current Legacy vs Modern reviews
echo "Recording initial database state..."
LEGACY_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Reviews WHERE Date < '2015-01-01'" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('result', [{}])[0].get('cnt', 0))")

MODERN_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Reviews WHERE Date >= '2015-01-01'" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('result', [{}])[0].get('cnt', 0))")

echo "Initial State: Legacy (<2015)=${LEGACY_COUNT}, Modern (>=2015)=${MODERN_COUNT}"

# Save to JSON for the verifier to use later
cat > /tmp/initial_db_state.json << EOF
{
    "legacy_count": ${LEGACY_COUNT},
    "modern_count": ${MODERN_COUNT},
    "timestamp": "$(date -Iseconds)"
}
EOF

# --- UI SETUP ---
# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="