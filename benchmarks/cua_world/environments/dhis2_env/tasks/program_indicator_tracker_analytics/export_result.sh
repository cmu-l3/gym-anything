#!/bin/bash
# Export script for Program Indicator Tracker Analytics task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
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

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00.000")
INITIAL_ANALYTICS_TIME=$(cat /tmp/initial_analytics_time 2>/dev/null || echo "None")

echo "Checking for new Program Indicators created after $TASK_START_ISO..."

# 1. Fetch new Program Indicators
# Note: filtering by created might need strict ISO format. If strictly ge fails, we fetch all sorted by created:desc and filter in python
PI_RESPONSE=$(dhis2_api "programIndicators?fields=id,displayName,shortName,analyticsType,aggregationType,program[id,displayName],created&order=created:desc&pageSize=20&paging=false" 2>/dev/null)

# 2. Check current Analytics Table status
SYSTEM_INFO=$(dhis2_api "system/info" 2>/dev/null)

# 3. Check for new Visualizations
VIZ_RESPONSE=$(dhis2_api "visualizations?fields=id,displayName,created&order=created:desc&pageSize=20&paging=false" 2>/dev/null)

# Process results with Python
python3 << PYEOF > /tmp/program_indicator_tracker_analytics_result.json
import json
import sys
from datetime import datetime

def parse_dhis_date(date_str):
    if not date_str: return None
    # Handle standard ISO format variations
    try:
        return datetime.fromisoformat(date_str.replace('Z', '+00:00'))
    except:
        pass
    # Fallback for Java timestamps
    try:
        return datetime.strptime(date_str.split('.')[0], "%Y-%m-%dT%H:%M:%S")
    except:
        return None

try:
    task_start_iso = "$TASK_START_ISO"
    task_start = parse_dhis_date(task_start_iso)
    
    # Load API responses
    pi_data = json.loads('''$PI_RESPONSE''')
    sys_info = json.loads('''$SYSTEM_INFO''')
    viz_data = json.loads('''$VIZ_RESPONSE''')
    
    result = {
        "task_start_iso": task_start_iso,
        "new_program_indicators": [],
        "analytics_generated": False,
        "new_visualizations": [],
        "initial_analytics_time": "$INITIAL_ANALYTICS_TIME",
        "current_analytics_time": sys_info.get("lastAnalyticsTableSuccess", "None")
    }

    # Filter PIs
    for pi in pi_data.get("programIndicators", []):
        created = parse_dhis_date(pi.get("created"))
        if created and task_start and created > task_start:
            result["new_program_indicators"].append({
                "name": pi.get("displayName"),
                "shortName": pi.get("shortName"),
                "analyticsType": pi.get("analyticsType"),
                "program": pi.get("program", {}).get("displayName"),
                "aggregationType": pi.get("aggregationType")
            })

    # Filter Visualizations
    for viz in viz_data.get("visualizations", []):
        created = parse_dhis_date(viz.get("created"))
        if created and task_start and created > task_start:
            result["new_visualizations"].append({
                "name": viz.get("displayName")
            })

    # Check Analytics Timestamp
    curr_analytics = sys_info.get("lastAnalyticsTableSuccess")
    init_analytics = "$INITIAL_ANALYTICS_TIME"
    
    if curr_analytics and curr_analytics != init_analytics:
        # Also verify it's recent (after task start)
        analytics_time = parse_dhis_date(curr_analytics)
        if analytics_time and task_start and analytics_time > task_start:
            result["analytics_generated"] = True
    
    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({"error": str(e)}))

PYEOF

echo "Result JSON generated:"
cat /tmp/program_indicator_tracker_analytics_result.json

echo "=== Export Complete ==="