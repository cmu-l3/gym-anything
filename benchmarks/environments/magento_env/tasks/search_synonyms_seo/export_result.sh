#!/bin/bash
# Export script for Search Synonyms SEO task

echo "=== Exporting Search Synonyms Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current counts
CURRENT_COUNT=$(magento_query "SELECT COUNT(*) FROM search_synonyms" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_synonym_count 2>/dev/null || echo "0")

echo "Synonym count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Dump all synonyms for Python verification
# We select group_id, synonyms (comma separated), and store_id
echo "Dumping search_synonyms table..."
# Using magento_query which returns tab-separated values without headers
# We want to use python to parse this carefully, so we'll output raw data to a file
magento_query "SELECT group_id, synonyms, store_id FROM search_synonyms" > /tmp/synonyms_dump.txt 2>/dev/null || true

# Debug output
echo "--- DB Dump Preview ---"
head -n 5 /tmp/synonyms_dump.txt
echo "-----------------------"

# Read the dump file into a JSON structure using python to avoid bash parsing hell
# We embed a small python script to convert the tab-separated dump to JSON
python3 -c "
import json
import sys

synonyms_list = []
try:
    with open('/tmp/synonyms_dump.txt', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 2:
                # schema: group_id, synonyms, store_id (optional if missing)
                group_id = parts[0]
                terms = parts[1]
                store_id = parts[2] if len(parts) > 2 else '0'
                synonyms_list.append({
                    'group_id': group_id,
                    'synonyms': terms,
                    'store_id': store_id
                })
except Exception as e:
    sys.stderr.write(f'Error parsing dump: {e}\n')

output = {
    'initial_count': int('$INITIAL_COUNT'),
    'current_count': int('$CURRENT_COUNT'),
    'synonym_groups': synonyms_list,
    'export_timestamp': '$(date -Iseconds)'
}

with open('/tmp/search_synonyms_result.json', 'w') as f:
    json.dump(output, f)
"

# Set permissions
chmod 666 /tmp/search_synonyms_result.json 2>/dev/null || sudo chmod 666 /tmp/search_synonyms_result.json 2>/dev/null || true

echo ""
cat /tmp/search_synonyms_result.json
echo ""
echo "=== Export Complete ==="