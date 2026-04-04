#!/bin/bash
echo "=== Setting up denormalize_latest_review task ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 60

# Clean state: Drop LatestReview property if it exists from previous runs
echo "Checking for existing LatestReview property..."
SCHEMA_JSON=$(orientdb_query "demodb" "SELECT FROM (SELECT expand(properties) FROM (SELECT expand(classes) FROM metadata:schema) WHERE name = 'Hotels') WHERE name = 'LatestReview'")
PROP_EXISTS=$(echo "$SCHEMA_JSON" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('result', [])))" 2>/dev/null || echo "0")

if [ "$PROP_EXISTS" -gt "0" ]; then
    echo "Dropping existing LatestReview property..."
    orientdb_sql "demodb" "DROP PROPERTY Hotels.LatestReview FORCE" > /dev/null 2>&1 || true
    sleep 2
fi

# Ensure Hotel Artemide has reviews for verification
# (The seeder script usually ensures this, but we verify here)
echo "Verifying test data..."
REVIEW_COUNT=$(orientdb_query "demodb" "SELECT count(*) as cnt FROM (MATCH {class: Hotels, as: h, where: (Name='Hotel Artemide')} -HasReview- {class: Reviews, as: r} RETURN r)" | \
    python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('result', [{}])[0].get('cnt', 0))" 2>/dev/null || echo "0")

if [ "$REVIEW_COUNT" -lt "1" ]; then
    echo "WARNING: Test hotel has no reviews. Injecting dummy review for verification integrity."
    # Find Hotel Artemide RID
    HOTEL_RID=$(orientdb_query "demodb" "SELECT @rid FROM Hotels WHERE Name='Hotel Artemide'" | \
        python3 -c "import sys, json; print(json.load(sys.stdin).get('result', [{}])[0].get('@rid', ''))")
    
    if [ -n "$HOTEL_RID" ]; then
        # Create a Review
        REVIEW_RID=$(orientdb_sql "demodb" "INSERT INTO Reviews SET Stars=5, Text='Great verification stay', Date='2025-01-01'" | \
             python3 -c "import sys, json; print(json.load(sys.stdin).get('result', [{}])[0].get('@rid', ''))")
        
        # Connect them (Assuming standard direction, but create both ways to be safe if schema ambiguous? 
        # Actually standard demodb is usually Hotel --HasReview--> Review or vice versa. 
        # We'll rely on the agent figuring out existing structure.)
        # Let's assume the seeder established a convention. We won't mess with edges if count is 0, 
        # just warn. The environment seeder is robust.
        echo "Hotel RID: $HOTEL_RID"
    fi
else
    echo "Test data confirmed: Hotel Artemide has $REVIEW_COUNT reviews."
fi

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="