#!/bin/bash
# Export result for standardize_journal_abbreviations task

echo "=== Exporting task result ==="

DB="/home/ga/Zotero/zotero.sqlite"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper function to get publication title for a paper title substring
get_pub_title() {
    local title_pattern="$1"
    sqlite3 "$DB" <<EOF
SELECT v_pub.value
FROM items i
JOIN itemData d_title ON i.itemID = d_title.itemID
JOIN itemDataValues v_title ON d_title.valueID = v_title.valueID
JOIN itemData d_pub ON i.itemID = d_pub.itemID
JOIN itemDataValues v_pub ON d_pub.valueID = v_pub.valueID
WHERE d_title.fieldID = 1          -- Title field
  AND v_title.value LIKE '${title_pattern}%'
  AND d_pub.fieldID = 38;          -- Publication field
EOF
}

# Helper function to check if item was modified recently
get_modified_status() {
    local title_pattern="$1"
    local start_time=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
    
    # Check clientDateModified or dateModified
    # Zotero stores dates as strings 'YYYY-MM-DD HH:MM:SS', we need to compare to unix timestamp
    # We'll just fetch the string and let python handle the comparison or use sqlite datetime
    sqlite3 "$DB" <<EOF
SELECT CASE 
    WHEN strftime('%s', dateModified) > $start_time THEN 'true' 
    ELSE 'false' 
END
FROM items i
JOIN itemData d ON i.itemID = d.itemID
JOIN itemDataValues v ON d.valueID = v.valueID
WHERE d.fieldID = 1 AND v.value LIKE '${title_pattern}%';
EOF
}

# Collect data
EINSTEIN_PUB=$(get_pub_title "On the Electrodynamics of Moving Bodies")
EINSTEIN_MOD=$(get_modified_status "On the Electrodynamics of Moving Bodies")

MCCARTHY_PUB=$(get_pub_title "Recursive Functions of Symbolic Expressions")
MCCARTHY_MOD=$(get_modified_status "Recursive Functions of Symbolic Expressions")

DIJKSTRA_PUB=$(get_pub_title "A Note on Two Problems in Connexion with Graphs")
DIJKSTRA_MOD=$(get_modified_status "A Note on Two Problems in Connexion with Graphs")

SHANNON_PUB=$(get_pub_title "A Mathematical Theory of Communication")
SHANNON_MOD=$(get_modified_status "A Mathematical Theory of Communication")

# Create JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "einstein": {
        "pub_title": "$EINSTEIN_PUB",
        "modified": $EINSTEIN_MOD
    },
    "mccarthy": {
        "pub_title": "$MCCARTHY_PUB",
        "modified": $MCCARTHY_MOD
    },
    "dijkstra": {
        "pub_title": "$DIJKSTRA_PUB",
        "modified": $DIJKSTRA_MOD
    },
    "shannon": {
        "pub_title": "$SHANNON_PUB",
        "modified": $SHANNON_MOD
    },
    "task_start_time": $(cat /tmp/task_start_time 2>/dev/null || echo "0"),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="