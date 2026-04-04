#!/bin/bash
set -e
echo "=== Setting up Full-Text Search Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 60

# Clean state: Remove the output file if it exists
OUTPUT_FILE="/home/ga/Documents/fulltext_search_results.json"
rm -f "$OUTPUT_FILE"
mkdir -p /home/ga/Documents

# Clean state: Drop existing Lucene indexes if they exist
# This ensures the agent must actually create them
echo "Cleaning up any existing Lucene indexes..."

# Helper to check and drop index
drop_index_if_exists() {
    local db=$1
    local class=$2
    local property=$3
    
    # Get class definition
    CLASS_DEF=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/${db}" | \
        python3 -c "import sys, json; 
data=json.load(sys.stdin); 
cls=next((c for c in data.get('classes',[]) if c['name']=='${class}'), {}); 
print(json.dumps(cls.get('indexes', [])))")
    
    # Find any index on the property that is FULLTEXT/LUCENE
    INDEX_NAME=$(echo "$CLASS_DEF" | python3 -c "import sys, json; 
indexes=json.load(sys.stdin); 
idx=next((i['name'] for i in indexes if '${property}' in i.get('fields',[]) and i.get('type')=='FULLTEXT'), None); 
print(idx if idx else '')")
    
    if [ -n "$INDEX_NAME" ]; then
        echo "Dropping pre-existing index: $INDEX_NAME"
        orientdb_sql "$db" "DROP INDEX $INDEX_NAME" > /dev/null
    fi
}

drop_index_if_exists "demodb" "Hotels" "Name"
drop_index_if_exists "demodb" "Restaurants" "Name"

# Ensure Firefox is open to OrientDB Studio
echo "Launching Studio..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="