#!/bin/bash
echo "=== Exporting fix_single_field_author_errors result ==="

DB="/home/ga/Zotero/zotero.sqlite"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper function to get author data as JSON object
get_author_data() {
    local title="$1"
    local original_name="$2" # To help find the right creator if name changed
    
    # We query by title to find the item, then get the first creator
    # We output a JSON object: {"fieldMode": X, "lastName": "Y", "firstName": "Z"}
    
    sqlite3 "$DB" <<EOF
SELECT json_object(
    'title', '$title',
    'fieldMode', c.fieldMode,
    'lastName', c.lastName,
    'firstName', c.firstName
)
FROM items i
JOIN itemData d ON i.itemID = d.itemID
JOIN itemDataValues v ON d.valueID = v.valueID
JOIN itemCreators ic ON i.itemID = ic.itemID
JOIN creators c ON ic.creatorID = c.creatorID
WHERE d.fieldID = 1 
  AND v.value = '$title' 
  AND ic.orderIndex = 0;
EOF
}

# Extract data for the 3 targets
echo "Querying database..."
SHANNON_JSON=$(get_author_data "A Mathematical Theory of Communication")
TURING_JSON=$(get_author_data "Computing Machinery and Intelligence")
HUFFMAN_JSON=$(get_author_data "A Method for the Construction of Minimum-Redundancy Codes")

# Handle empty results (if item not found)
if [ -z "$SHANNON_JSON" ]; then SHANNON_JSON="null"; fi
if [ -z "$TURING_JSON" ]; then TURING_JSON="null"; fi
if [ -z "$HUFFMAN_JSON" ]; then HUFFMAN_JSON="null"; fi

# Construct final JSON
cat > /tmp/task_result.json <<EOF
{
    "shannon": $SHANNON_JSON,
    "turing": $TURING_JSON,
    "huffman": $HUFFMAN_JSON,
    "timestamp": $(date +%s)
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="