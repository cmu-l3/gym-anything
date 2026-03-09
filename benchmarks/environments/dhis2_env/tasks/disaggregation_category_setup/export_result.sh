#!/bin/bash
# Export script for Disaggregation Category Setup task

echo "=== Exporting Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence
take_screenshot /tmp/task_end_screenshot.png

# Get task start time
TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00")

echo "Querying DHIS2 Metadata API..."

# 1. Query Category Options
# Filter for names containing 'Trimester'
OPTIONS_JSON=$(dhis2_api "categoryOptions?filter=name:ilike:Trimester&fields=id,name,created,shortName&paging=false")

# 2. Query Categories
# Filter for names containing 'Pregnancy' and include children (categoryOptions)
CATEGORIES_JSON=$(dhis2_api "categories?filter=name:ilike:Pregnancy&fields=id,name,created,dataDimensionType,categoryOptions[id,name]&paging=false")

# 3. Query Category Combinations
# Filter for names containing 'Pregnancy' and include children (categories)
COMBOS_JSON=$(dhis2_api "categoryCombos?filter=name:ilike:Pregnancy&fields=id,name,created,dataDimensionType,categories[id,name]&paging=false")

# Combine all data into a single JSON structure using Python
# We also perform date parsing here to calculate 'created_during_task' flags
python3 -c "
import json
import sys
from datetime import datetime

try:
    task_start_iso = '$TASK_START_ISO'
    # Simple ISO parse (handling potential Z or timezone differences strictly if needed, 
    # but for this env simple comparison often suffices or string comparison if format is identical)
    # DHIS2 returns ISO dates.
    
    options_data = json.loads('''$OPTIONS_JSON''')
    categories_data = json.loads('''$CATEGORIES_JSON''')
    combos_data = json.loads('''$COMBOS_JSON''')
    
    result = {
        'task_start': task_start_iso,
        'options': options_data.get('categoryOptions', []),
        'categories': categories_data.get('categories', []),
        'combos': combos_data.get('categoryCombos', []),
        'timestamp': datetime.now().isoformat()
    }
    
    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({'error': str(e)}))

" > /tmp/task_result.json

# Save result to final location
cp /tmp/task_result.json /tmp/disaggregation_setup_result.json
chmod 666 /tmp/disaggregation_setup_result.json

echo "Export summary:"
echo "  Options found: $(jq '.options | length' /tmp/task_result.json)"
echo "  Categories found: $(jq '.categories | length' /tmp/task_result.json)"
echo "  Combos found: $(jq '.combos | length' /tmp/task_result.json)"

echo "=== Export Complete ==="