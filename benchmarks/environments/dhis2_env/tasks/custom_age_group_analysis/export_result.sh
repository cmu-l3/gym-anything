#!/bin/bash
# Export script for Custom Age Group Analysis task

echo "=== Exporting Custom Age Group Analysis Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

echo "Querying DHIS2 metadata..."

# 1. Fetch Category Option Groups (looking for "Under 5" and "Over 5")
# We filter broadly by name to catch variations
COG_JSON=$(dhis2_api "categoryOptionGroups?fields=id,name,categoryOptions[id,name]&filter=name:ilike:Year&paging=false" 2>/dev/null)

# 2. Fetch Category Option Group Sets (looking for "Broad Age")
COGS_JSON=$(dhis2_api "categoryOptionGroupSets?fields=id,name,dataDimension,categoryOptionGroups[id,name]&filter=name:ilike:Broad+Age&paging=false" 2>/dev/null)

# 3. Fetch recent Visualizations
# We get visualizations created after task start
VIZ_JSON=$(dhis2_api "visualizations?fields=id,displayName,created,columnDimensions,rowDimensions,filterDimensions&filter=created:ge:${TASK_START_ISO}&paging=false" 2>/dev/null)

# 4. Fetch all Category Options to verify content of groups (e.g. check if options are actually age related)
# Limit to 200 to avoid huge payload, hoping the demo db isn't massive or we find relevant ones
# We filter for age-looking options
AGE_OPTIONS_JSON=$(dhis2_api "categoryOptions?fields=id,name&filter=name:ilike:year&filter=name:ilike:month&paging=false" 2>/dev/null)


# Combine into a single JSON using Python
python3 -c "
import json, sys

try:
    cog_data = json.loads('''$COG_JSON''')
    cogs_data = json.loads('''$COGS_JSON''')
    viz_data = json.loads('''$VIZ_JSON''')
    age_opt_data = json.loads('''$AGE_OPTIONS_JSON''')

    result = {
        'categoryOptionGroups': cog_data.get('categoryOptionGroups', []),
        'categoryOptionGroupSets': cogs_data.get('categoryOptionGroupSets', []),
        'visualizations': viz_data.get('visualizations', []),
        'ageOptions': age_opt_data.get('categoryOptions', []),
        'task_start_iso': '$TASK_START_ISO'
    }
    
    with open('/tmp/custom_age_group_analysis_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
    print('Exported JSON successfully')

except Exception as e:
    print(f'Error processing JSON: {e}')
    # Write a failure JSON
    with open('/tmp/custom_age_group_analysis_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

chmod 666 /tmp/custom_age_group_analysis_result.json 2>/dev/null || true

echo "=== Export Complete ==="
cat /tmp/custom_age_group_analysis_result.json | head -n 20
echo "..."