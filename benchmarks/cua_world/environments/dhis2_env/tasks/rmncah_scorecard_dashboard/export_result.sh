#!/bin/bash
# Export script for RMNCAH Scorecard Dashboard task

echo "=== Exporting RMNCAH Scorecard Dashboard Result ==="

source /workspace/scripts/task_utils.sh

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

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

# Load initial IDs for new-item detection
load_initial_ids() {
    local file="$1"
    cat "$file" 2>/dev/null | tr '\n' ' ' || echo ""
}

# ---------------------------------------------------------------
# 1. Check for new Indicators
# ---------------------------------------------------------------
echo "Checking for new indicators..."
INDICATOR_RESULT=$(curl -s -u admin:district "http://localhost:8080/api/indicators?fields=id,displayName,created,numerator,denominator,indicatorType%5Bid,name,factor%5D&paging=false" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('Z','+00:00').replace('+0000','+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    initial_ids = set()
    try:
        with open('/tmp/initial_indicator_ids') as f:
            initial_ids = set(line.strip() for line in f if line.strip())
    except:
        pass

    new_indicators = []
    for ind in data.get('indicators', []):
        ind_id = ind.get('id', '')
        is_new = ind_id not in initial_ids

        created_str = ind.get('created', '2020-01-01T00:00:00')
        try:
            created = datetime.fromisoformat(created_str.replace('Z','+00:00').replace('+0000','+00:00'))
            created_during_task = created >= task_start
        except:
            created_during_task = False

        if is_new or created_during_task:
            name = ind.get('displayName', '')
            numerator = ind.get('numerator', '')
            denominator = ind.get('denominator', '')
            ind_type = ind.get('indicatorType', {})

            # Classify the indicator
            name_lower = name.lower()
            is_anc = any(k in name_lower for k in ['anc', 'completion', 'coverage', '4th'])
            is_dropout = any(k in name_lower for k in ['dropout', 'drop', 'penta'])

            # Check if numerator has subtraction (key signal for dropout indicator)
            has_subtraction = '-' in numerator and '#{' in numerator

            new_indicators.append({
                'id': ind_id,
                'name': name,
                'numerator': numerator,
                'denominator': denominator,
                'factor': ind_type.get('factor', 1),
                'indicator_type_name': ind_type.get('name', ''),
                'is_anc_indicator': is_anc,
                'is_dropout_indicator': is_dropout,
                'has_subtraction_in_numerator': has_subtraction,
                'numerator_has_formula': numerator != '' and numerator != '1',
                'denominator_has_formula': denominator != '' and denominator != '1'
            })

    # Find best ANC match and best dropout match
    anc_indicators = [i for i in new_indicators if i['is_anc_indicator']]
    dropout_indicators = [i for i in new_indicators if i['is_dropout_indicator']]

    print(json.dumps({
        'new_indicator_count': len(new_indicators),
        'anc_indicator_found': len(anc_indicators) > 0,
        'anc_indicator': anc_indicators[0] if anc_indicators else None,
        'dropout_indicator_found': len(dropout_indicators) > 0,
        'dropout_indicator': dropout_indicators[0] if dropout_indicators else None,
        'all_new_indicators': new_indicators
    }))
except Exception as e:
    print(json.dumps({'new_indicator_count': 0, 'error': str(e)}))
" 2>/dev/null || echo '{"new_indicator_count": 0}')

echo "Indicator result: $INDICATOR_RESULT"

# ---------------------------------------------------------------
# 2. Check for new Legend Sets
# ---------------------------------------------------------------
echo "Checking for new legend sets..."
LEGEND_RESULT=$(curl -s -u admin:district "http://localhost:8080/api/legendSets?fields=id,displayName,created,legends%5Bid,name,startValue,endValue,color%5D&paging=false" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('Z','+00:00').replace('+0000','+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    initial_ids = set()
    try:
        with open('/tmp/initial_legend_ids') as f:
            initial_ids = set(line.strip() for line in f if line.strip())
    except:
        pass

    new_legends = []
    for ls in data.get('legendSets', []):
        ls_id = ls.get('id', '')
        is_new = ls_id not in initial_ids

        created_str = ls.get('created', '2020-01-01T00:00:00')
        try:
            created = datetime.fromisoformat(created_str.replace('Z','+00:00').replace('+0000','+00:00'))
            created_during_task = created >= task_start
        except:
            created_during_task = False

        name = ls.get('displayName', '')
        name_lower = name.lower()

        if is_new or created_during_task:
            items = ls.get('legends', [])
            colors = set(l.get('color', '').lower() for l in items if l.get('color'))
            min_start = min([float(l.get('startValue', 0)) for l in items]) if items else -1
            max_end = max([float(l.get('endValue', 0)) for l in items]) if items else -1

            new_legends.append({
                'id': ls_id,
                'name': name,
                'item_count': len(items),
                'distinct_color_count': len(colors),
                'min_start': min_start,
                'max_end': max_end,
                'is_rmncah': any(k in name_lower for k in ['rmncah', 'performance']),
                'items': [{'name': l.get('name',''), 'start': l.get('startValue'), 'end': l.get('endValue'), 'color': l.get('color','')} for l in items]
            })

    rmncah_legends = [l for l in new_legends if l['is_rmncah']]

    print(json.dumps({
        'new_legend_count': len(new_legends),
        'rmncah_legend_found': len(rmncah_legends) > 0,
        'best_match': rmncah_legends[0] if rmncah_legends else (new_legends[0] if new_legends else None)
    }))
except Exception as e:
    print(json.dumps({'new_legend_count': 0, 'error': str(e)}))
" 2>/dev/null || echo '{"new_legend_count": 0}')

echo "Legend result: $LEGEND_RESULT"

# ---------------------------------------------------------------
# 3. Check for new Visualizations
# ---------------------------------------------------------------
echo "Checking for new visualizations..."
VIZ_RESULT=$(curl -s -u admin:district "http://localhost:8080/api/visualizations?fields=id,displayName,created,type,legendSet%5Bid,displayName%5D,legendDisplayStrategy,dataDimensionItems%5BdataDimensionItemType,indicator%5Bid,displayName%5D%5D&paging=false" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('Z','+00:00').replace('+0000','+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    initial_ids = set()
    try:
        with open('/tmp/initial_viz_ids') as f:
            initial_ids = set(line.strip() for line in f if line.strip())
    except:
        pass

    new_viz = []
    for v in data.get('visualizations', []):
        v_id = v.get('id', '')
        is_new = v_id not in initial_ids

        created_str = v.get('created', '2020-01-01T00:00:00')
        try:
            created = datetime.fromisoformat(created_str.replace('Z','+00:00').replace('+0000','+00:00'))
            created_during_task = created >= task_start
        except:
            created_during_task = False

        if is_new or created_during_task:
            name = v.get('displayName', '')
            name_lower = name.lower()

            # Check if legend is applied
            legend_set = v.get('legendSet')
            legend_applied = legend_set is not None
            legend_name = legend_set.get('displayName', '') if legend_set else ''

            # Check data dimension items for indicators
            ddi = v.get('dataDimensionItems', [])
            indicator_names = []
            for item in ddi:
                if item.get('dataDimensionItemType') == 'INDICATOR':
                    ind = item.get('indicator', {})
                    if ind.get('displayName'):
                        indicator_names.append(ind['displayName'])

            is_scorecard = any(k in name_lower for k in ['rmncah', 'scorecard', 'district'])

            new_viz.append({
                'id': v_id,
                'name': name,
                'type': v.get('type', ''),
                'is_pivot_table': v.get('type') == 'PIVOT_TABLE',
                'legend_applied': legend_applied,
                'legend_name': legend_name,
                'indicator_names': indicator_names,
                'indicator_count': len(indicator_names),
                'is_scorecard': is_scorecard
            })

    scorecard_viz = [v for v in new_viz if v['is_scorecard']]

    print(json.dumps({
        'new_viz_count': len(new_viz),
        'scorecard_found': len(scorecard_viz) > 0,
        'best_match': scorecard_viz[0] if scorecard_viz else (new_viz[0] if new_viz else None),
        'all_new_viz': new_viz
    }))
except Exception as e:
    print(json.dumps({'new_viz_count': 0, 'error': str(e)}))
" 2>/dev/null || echo '{"new_viz_count": 0}')

echo "Visualization result: $VIZ_RESULT"

# ---------------------------------------------------------------
# 4. Check for new Dashboards
# ---------------------------------------------------------------
echo "Checking for new dashboards..."
DASHBOARD_RESULT=$(curl -s -u admin:district "http://localhost:8080/api/dashboards?fields=id,displayName,created,dashboardItems%5Bid,type,visualization%5Bid,displayName%5D,map%5Bid,displayName%5D%5D&paging=false" 2>/dev/null | \
python3 -c "
import json, sys
from datetime import datetime

try:
    data = json.load(sys.stdin)
    task_start_iso = '$TASK_START_ISO'
    try:
        task_start = datetime.fromisoformat(task_start_iso.replace('Z','+00:00').replace('+0000','+00:00'))
    except:
        task_start = datetime(2020, 1, 1)

    initial_ids = set()
    try:
        with open('/tmp/initial_dashboard_ids') as f:
            initial_ids = set(line.strip() for line in f if line.strip())
    except:
        pass

    new_dashboards = []
    for d in data.get('dashboards', []):
        d_id = d.get('id', '')
        is_new = d_id not in initial_ids

        created_str = d.get('created', '2020-01-01T00:00:00')
        try:
            created = datetime.fromisoformat(created_str.replace('Z','+00:00').replace('+0000','+00:00'))
            created_during_task = created >= task_start
        except:
            created_during_task = False

        if is_new or created_during_task:
            name = d.get('displayName', '')
            items = d.get('dashboardItems', [])
            item_count = len(items)

            # Collect item details
            item_details = []
            for item in items:
                detail = {'type': item.get('type', '')}
                viz = item.get('visualization')
                if viz:
                    detail['visualization_name'] = viz.get('displayName', '')
                m = item.get('map')
                if m:
                    detail['map_name'] = m.get('displayName', '')
                item_details.append(detail)

            name_lower = name.lower()
            is_rmncah = any(k in name_lower for k in ['rmncah', 'scorecard'])

            new_dashboards.append({
                'id': d_id,
                'name': name,
                'item_count': item_count,
                'items': item_details,
                'is_rmncah': is_rmncah
            })

    rmncah_dashboards = [d for d in new_dashboards if d['is_rmncah']]

    print(json.dumps({
        'new_dashboard_count': len(new_dashboards),
        'rmncah_dashboard_found': len(rmncah_dashboards) > 0,
        'best_match': rmncah_dashboards[0] if rmncah_dashboards else (new_dashboards[0] if new_dashboards else None)
    }))
except Exception as e:
    print(json.dumps({'new_dashboard_count': 0, 'error': str(e)}))
" 2>/dev/null || echo '{"new_dashboard_count": 0}')

echo "Dashboard result: $DASHBOARD_RESULT"

# ---------------------------------------------------------------
# 5. Get data element UIDs for formula cross-reference
# ---------------------------------------------------------------
echo "Getting data element UIDs for formula verification..."
DE_UIDS=$(curl -s -u admin:district "http://localhost:8080/api/dataElements?filter=name:in:%5BANC+1st+visit,ANC+4th+or+more+visits,Penta1+doses+given,Penta3+doses+given%5D&fields=id,name&paging=false" 2>/dev/null | \
python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    result = {}
    for de in data.get('dataElements', []):
        result[de['name']] = de['id']
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null || echo '{}')

echo "Data element UIDs: $DE_UIDS"

# ---------------------------------------------------------------
# Combine all results
# ---------------------------------------------------------------
cat > /tmp/rmncah_scorecard_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "indicator_check": $INDICATOR_RESULT,
    "legend_check": $LEGEND_RESULT,
    "visualization_check": $VIZ_RESULT,
    "dashboard_check": $DASHBOARD_RESULT,
    "data_element_uids": $DE_UIDS,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/rmncah_scorecard_result.json 2>/dev/null || true
echo ""
echo "Result saved to /tmp/rmncah_scorecard_result.json"
cat /tmp/rmncah_scorecard_result.json
echo ""
echo "=== Export Complete ==="
