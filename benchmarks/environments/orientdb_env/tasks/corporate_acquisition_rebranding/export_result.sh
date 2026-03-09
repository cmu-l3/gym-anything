#!/bin/bash
echo "=== Exporting Corporate Acquisition Rebranding Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- DATA EXTRACTION ---
# We use curl/sql to extract the current state of the database into a JSON structure
# tailored for the verifier.

echo "Querying database state..."

# 1. Check Schema (Classes)
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

# 2. Check Brands Vertex
BRANDS_JSON=$(orientdb_sql "demodb" "SELECT Name, @rid as rid FROM Brands")

# 3. Check Target Hotels (We look for hotels that SHOULD have been changed)
# We look for hotels with the new Type OR the new Suffix to see if they were partially or fully updated.
# We also check if any 'Boutique' hotels remain (should be 0).

# Hotels that have the new type
NEW_TYPE_HOTELS=$(orientdb_sql "demodb" "SELECT Name, Type, out('BelongsTo').Name as BrandLinks FROM Hotels WHERE Type='Luxury Collection'")

# Hotels that have the suffix
SUFFIX_HOTELS=$(orientdb_sql "demodb" "SELECT Name, Type FROM Hotels WHERE Name LIKE '% - The Collections'")

# Remaining Boutique hotels (Should be 0 if all converted)
REMAINING_BOUTIQUE=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels WHERE Type='Boutique'")

# 4. Check Non-Target Hotels (Safety check)
# Pick a known non-boutique type, e.g., 'Luxury' or 'Historic'
NON_TARGET_SAMPLE=$(orientdb_sql "demodb" "SELECT Name, Type FROM Hotels WHERE Type='Luxury' LIMIT 5")

# Create the result JSON
TEMP_JSON=$(mktemp /tmp/rebranding_result.XXXXXX.json)
python3 -c "
import json
import sys

try:
    schema = json.loads('''$SCHEMA_JSON''')
    brands = json.loads('''$BRANDS_JSON''')
    new_type_hotels = json.loads('''$NEW_TYPE_HOTELS''')
    suffix_hotels = json.loads('''$SUFFIX_HOTELS''')
    remaining_boutique = json.loads('''$REMAINING_BOUTIQUE''')
    non_target = json.loads('''$NON_TARGET_SAMPLE''')

    # Parse Schema for specific classes
    classes = [c['name'] for c in schema.get('classes', [])]
    
    result = {
        'timestamp': $TASK_END,
        'classes_exist': {
            'Brands': 'Brands' in classes,
            'BelongsTo': 'BelongsTo' in classes
        },
        'brands_data': brands.get('result', []),
        'converted_hotels_by_type': new_type_hotels.get('result', []),
        'converted_hotels_by_name': suffix_hotels.get('result', []),
        'remaining_boutique_count': remaining_boutique.get('result', [{}])[0].get('cnt', 0),
        'non_target_sample': non_target.get('result', [])
    }
    
    print(json.dumps(result, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > "$TEMP_JSON"

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="