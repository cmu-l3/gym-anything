#!/bin/bash
echo "=== Exporting Full-Text Search Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/fulltext_search_results.json"

# 1. Check Output File
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Database State (Do indexes exist?)
# We use Python to parse the OrientDB schema JSON
HOTELS_INDEX_EXISTS="false"
RESTAURANTS_INDEX_EXISTS="false"

# Get schema for Hotels
echo "Checking Hotels schema..."
HOTELS_SCHEMA=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" | \
    python3 -c "import sys, json; 
data=json.load(sys.stdin); 
cls=next((c for c in data.get('classes',[]) if c['name']=='Hotels'), {}); 
print(json.dumps(cls))")

# Check for LUCENE FULLTEXT index on Name
HOTELS_INDEX_EXISTS=$(echo "$HOTELS_SCHEMA" | python3 -c "import sys, json; 
cls=json.load(sys.stdin); 
indexes=cls.get('indexes', []); 
found=any(i for i in indexes if 'Name' in i.get('fields',[]) and i.get('type')=='FULLTEXT' and i.get('algorithm')=='LUCENE'); 
print('true' if found else 'false')")

# Get schema for Restaurants
echo "Checking Restaurants schema..."
RESTAURANTS_SCHEMA=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" | \
    python3 -c "import sys, json; 
data=json.load(sys.stdin); 
cls=next((c for c in data.get('classes',[]) if c['name']=='Restaurants'), {}); 
print(json.dumps(cls))")

# Check for LUCENE FULLTEXT index on Name
RESTAURANTS_INDEX_EXISTS=$(echo "$RESTAURANTS_SCHEMA" | python3 -c "import sys, json; 
cls=json.load(sys.stdin); 
indexes=cls.get('indexes', []); 
found=any(i for i in indexes if 'Name' in i.get('fields',[]) and i.get('type')=='FULLTEXT' and i.get('algorithm')=='LUCENE'); 
print('true' if found else 'false')")

echo "Hotels Index: $HOTELS_INDEX_EXISTS"
echo "Restaurants Index: $RESTAURANTS_INDEX_EXISTS"

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Export Verification Data
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size": $OUTPUT_SIZE,
    "hotels_lucene_index_exists": $HOTELS_INDEX_EXISTS,
    "restaurants_lucene_index_exists": $RESTAURANTS_INDEX_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to final location with permissions
rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "=== Export complete ==="