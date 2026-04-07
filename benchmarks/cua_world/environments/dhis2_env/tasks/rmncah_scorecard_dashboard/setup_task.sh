#!/bin/bash
# Setup script for RMNCAH Scorecard Dashboard task

echo "=== Setting up RMNCAH Scorecard Dashboard Task ==="

source /workspace/scripts/task_utils.sh

# Inline fallbacks
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        local endpoint="$1"
        local method="${2:-GET}"
        curl -s -u admin:district -X "$method" "http://localhost:8080/api/$endpoint"
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
    }
fi

# Verify DHIS2 is running
echo "Checking DHIS2 health..."
for i in $(seq 1 6); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/api/system/info" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "401" ]; then
        echo "DHIS2 is responsive (HTTP $HTTP_CODE)"
        break
    fi
    echo "DHIS2 not ready (HTTP $HTTP_CODE), waiting 10s..."
    sleep 10
done

# Clean up any pre-existing items with matching names (for clean reruns)
echo "Cleaning up pre-existing RMNCAH items..."

# Delete pre-existing indicators matching our target names
for FILTER in "ANC+4th+Visit+Completion+Rate" "Penta1-Penta3+Dropout+Rate"; do
    EXISTING_ID=$(dhis2_api "indicators?filter=name:ilike:$FILTER&fields=id&paging=false" 2>/dev/null | \
        python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for ind in d.get('indicators', []):
        print(ind['id'])
except:
    pass
" 2>/dev/null)

    for IND_ID in $EXISTING_ID; do
        if [ -n "$IND_ID" ]; then
            echo "Deleting pre-existing indicator: $IND_ID"
            curl -s -u admin:district -X DELETE "http://localhost:8080/api/indicators/$IND_ID" > /dev/null 2>&1
        fi
    done
done

# Delete pre-existing legend sets matching RMNCAH
EXISTING_LS=$(dhis2_api "legendSets?filter=name:ilike:RMNCAH&fields=id&paging=false" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for ls in d.get('legendSets', []):
        print(ls['id'])
except:
    pass
" 2>/dev/null)

for LS_ID in $EXISTING_LS; do
    if [ -n "$LS_ID" ]; then
        echo "Deleting pre-existing legend set: $LS_ID"
        curl -s -u admin:district -X DELETE "http://localhost:8080/api/legendSets/$LS_ID" > /dev/null 2>&1
    fi
done

# Delete pre-existing visualizations matching RMNCAH
EXISTING_VIZ=$(dhis2_api "visualizations?filter=name:ilike:RMNCAH&fields=id&paging=false" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for v in d.get('visualizations', []):
        print(v['id'])
except:
    pass
" 2>/dev/null)

for VIZ_ID in $EXISTING_VIZ; do
    if [ -n "$VIZ_ID" ]; then
        echo "Deleting pre-existing visualization: $VIZ_ID"
        curl -s -u admin:district -X DELETE "http://localhost:8080/api/visualizations/$VIZ_ID" > /dev/null 2>&1
    fi
done

# Delete pre-existing dashboards matching RMNCAH
EXISTING_DASH=$(dhis2_api "dashboards?filter=name:ilike:RMNCAH&fields=id&paging=false" 2>/dev/null | \
    python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for d2 in d.get('dashboards', []):
        print(d2['id'])
except:
    pass
" 2>/dev/null)

for DASH_ID in $EXISTING_DASH; do
    if [ -n "$DASH_ID" ]; then
        echo "Deleting pre-existing dashboard: $DASH_ID"
        curl -s -u admin:district -X DELETE "http://localhost:8080/api/dashboards/$DASH_ID" > /dev/null 2>&1
    fi
done

# Record task start time AFTER cleanup
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso
TASK_START=$(cat /tmp/task_start_iso)
echo "Task start time: $TASK_START"

# Record baseline counts
echo "Recording baseline counts..."
INITIAL_IND_COUNT=$(dhis2_api "indicators?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_IND_COUNT" > /tmp/initial_indicator_count

INITIAL_LEGEND_COUNT=$(dhis2_api "legendSets?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_LEGEND_COUNT" > /tmp/initial_legend_count

INITIAL_VIZ_COUNT=$(dhis2_api "visualizations?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_VIZ_COUNT" > /tmp/initial_visualization_count

INITIAL_DASH_COUNT=$(dhis2_api "dashboards?paging=true&pageSize=1" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('pager',{}).get('total',0))" 2>/dev/null || echo "0")
echo "$INITIAL_DASH_COUNT" > /tmp/initial_dashboard_count

# Record all existing IDs for new-item detection
dhis2_api "indicators?fields=id&paging=false" 2>/dev/null | \
    python3 -c "import json,sys; print('\n'.join([x['id'] for x in json.load(sys.stdin).get('indicators',[])]))" > /tmp/initial_indicator_ids 2>/dev/null || echo "" > /tmp/initial_indicator_ids

dhis2_api "legendSets?fields=id&paging=false" 2>/dev/null | \
    python3 -c "import json,sys; print('\n'.join([x['id'] for x in json.load(sys.stdin).get('legendSets',[])]))" > /tmp/initial_legend_ids 2>/dev/null || echo "" > /tmp/initial_legend_ids

dhis2_api "visualizations?fields=id&paging=false" 2>/dev/null | \
    python3 -c "import json,sys; print('\n'.join([x['id'] for x in json.load(sys.stdin).get('visualizations',[])]))" > /tmp/initial_viz_ids 2>/dev/null || echo "" > /tmp/initial_viz_ids

dhis2_api "dashboards?fields=id&paging=false" 2>/dev/null | \
    python3 -c "import json,sys; print('\n'.join([x['id'] for x in json.load(sys.stdin).get('dashboards',[])]))" > /tmp/initial_dashboard_ids 2>/dev/null || echo "" > /tmp/initial_dashboard_ids

# Verify that required data elements exist in the system
echo "Verifying required data elements..."
for DE_NAME in "ANC 1st visit" "ANC 4th or more visits" "Penta1 doses given" "Penta3 doses given"; do
    ENCODED_NAME=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$DE_NAME'))")
    DE_CHECK=$(dhis2_api "dataElements?filter=name:eq:$ENCODED_NAME&fields=id,name&paging=false" 2>/dev/null | \
        python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('dataElements',[])))" 2>/dev/null || echo "0")
    echo "  Data element '$DE_NAME': $DE_CHECK found"
done

# Verify Percentage indicator type exists
PCTG_TYPE=$(dhis2_api "indicatorTypes?filter=factor:eq:100&fields=id,name,factor&paging=false" 2>/dev/null | \
    python3 -c "import json,sys; d=json.load(sys.stdin); types=d.get('indicatorTypes',[]); print(types[0]['id'] + ' (' + types[0]['name'] + ')' if types else 'NOT_FOUND')" 2>/dev/null || echo "NOT_FOUND")
echo "Per cent indicator type (factor 100): $PCTG_TYPE"

# Ensure analytics tables are populated so indicators produce data in visualizations
echo "Ensuring analytics tables are populated..."
ANALYTICS_COUNT=$(docker exec dhis2-db psql -U dhis -d dhis2 -t -c "SELECT COUNT(*) FROM analytics" 2>/dev/null | tr -d ' ')
if [ "$ANALYTICS_COUNT" = "0" ] || [ -z "$ANALYTICS_COUNT" ]; then
    echo "Analytics tables empty — triggering regeneration..."
    curl -s -u admin:district -X POST "http://localhost:8080/api/resourceTables/analytics" > /dev/null 2>&1
    # Wait for analytics to complete (check every 15s, up to 5 min)
    for i in $(seq 1 20); do
        sleep 15
        ANALYTICS_COUNT=$(docker exec dhis2-db psql -U dhis -d dhis2 -t -c "SELECT COUNT(*) FROM analytics" 2>/dev/null | tr -d ' ')
        if [ "$ANALYTICS_COUNT" -gt 0 ] 2>/dev/null; then
            echo "Analytics tables populated: $ANALYTICS_COUNT rows"
            break
        fi
        echo "  Waiting for analytics... ($i/20)"
    done
else
    echo "Analytics tables already populated: $ANALYTICS_COUNT rows"
fi

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
DHIS2_URL="http://localhost:8080"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
else
    su - ga -c "DISPLAY=:1 firefox '$DHIS2_URL' > /dev/null 2>&1 &" 2>/dev/null || true
    sleep 4
fi

# Wait for Firefox window
for i in $(seq 1 10); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|DHIS"; then
        break
    fi
    sleep 2
done

# Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task Start: $TASK_START"
echo "Initial Indicators: $INITIAL_IND_COUNT"
echo "Initial Legend Sets: $INITIAL_LEGEND_COUNT"
echo "Initial Visualizations: $INITIAL_VIZ_COUNT"
echo "Initial Dashboards: $INITIAL_DASH_COUNT"
echo "Percentage Indicator Type: $PCTG_TYPE"
echo "=== RMNCAH Scorecard Dashboard Task Setup Complete ==="
