#!/bin/bash
# Export script for District Immunization Completion Analysis task

echo "=== Exporting District Immunization Completion Analysis Result ==="

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
TASK_START_EPOCH=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' ' || echo "0")

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

            name_lower = name.lower()
            is_dropout = any(k in name_lower for k in ['dropout', 'immunization', 'completion', 'full'])

            # Check if numerator has subtraction (key signal for dropout formula)
            has_subtraction = '-' in numerator and '#{' in numerator

            new_indicators.append({
                'id': ind_id,
                'name': name,
                'numerator': numerator,
                'denominator': denominator,
                'factor': ind_type.get('factor', 1),
                'indicator_type_name': ind_type.get('name', ''),
                'is_dropout_indicator': is_dropout,
                'has_subtraction_in_numerator': has_subtraction,
                'numerator_has_formula': numerator != '' and numerator != '1',
                'denominator_has_formula': denominator != '' and denominator != '1'
            })

    dropout_indicators = [i for i in new_indicators if i['is_dropout_indicator']]

    print(json.dumps({
        'new_indicator_count': len(new_indicators),
        'dropout_indicator_found': len(dropout_indicators) > 0,
        'dropout_indicator': dropout_indicators[0] if dropout_indicators else (new_indicators[0] if new_indicators else None),
        'all_new_indicators': new_indicators
    }))
except Exception as e:
    print(json.dumps({'new_indicator_count': 0, 'error': str(e)}))
" 2>/dev/null || echo '{"new_indicator_count": 0}')

echo "Indicator result: $INDICATOR_RESULT"

# ---------------------------------------------------------------
# 2. Check for new Visualizations
# ---------------------------------------------------------------
echo "Checking for new visualizations..."
VIZ_RESULT=$(curl -s -u admin:district "http://localhost:8080/api/visualizations?fields=id,displayName,created,type,dataDimensionItems%5BdataDimensionItemType,indicator%5Bid,displayName%5D,dataElement%5Bid,displayName%5D%5D,periods,organisationUnits%5Bid,displayName%5D,organisationUnitLevels&paging=false" 2>/dev/null | \
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

            # Check data dimension items
            ddi = v.get('dataDimensionItems', [])
            indicator_names = []
            data_element_names = []
            for item in ddi:
                if item.get('dataDimensionItemType') == 'INDICATOR':
                    ind = item.get('indicator', {})
                    if ind.get('displayName'):
                        indicator_names.append(ind['displayName'])
                elif item.get('dataDimensionItemType') == 'DATA_ELEMENT':
                    de = item.get('dataElement', {})
                    if de.get('displayName'):
                        data_element_names.append(de['displayName'])

            # Check org units for Bo district facilities
            org_units = v.get('organisationUnits', [])
            org_unit_names = [ou.get('displayName', '') for ou in org_units]
            has_bo_units = any('bo' in n.lower() for n in org_unit_names) or len(org_units) > 5

            is_target = any(k in name_lower for k in ['bo', 'facility', 'immunization', 'dropout', 'analysis'])

            new_viz.append({
                'id': v_id,
                'name': name,
                'type': v.get('type', ''),
                'is_pivot_table': v.get('type') == 'PIVOT_TABLE',
                'indicator_names': indicator_names,
                'data_element_names': data_element_names,
                'indicator_count': len(indicator_names),
                'data_element_count': len(data_element_names),
                'org_unit_count': len(org_units),
                'has_bo_units': has_bo_units,
                'is_target': is_target
            })

    target_viz = [v for v in new_viz if v['is_target']]

    print(json.dumps({
        'new_viz_count': len(new_viz),
        'target_found': len(target_viz) > 0,
        'best_match': target_viz[0] if target_viz else (new_viz[0] if new_viz else None),
        'all_new_viz': new_viz
    }))
except Exception as e:
    print(json.dumps({'new_viz_count': 0, 'error': str(e)}))
" 2>/dev/null || echo '{"new_viz_count": 0}')

echo "Visualization result: $VIZ_RESULT"

# ---------------------------------------------------------------
# 3. Check Downloads for CSV/XLSX export
# ---------------------------------------------------------------
echo "Checking Downloads for exported files..."
DOWNLOADS_RESULT=$(python3 << 'PYEOF'
import os, json

downloads_dir = "/home/ga/Downloads"
task_start_epoch = int(open("/tmp/task_start_timestamp").read().strip() or "0")

new_files = []
if os.path.exists(downloads_dir):
    for fname in os.listdir(downloads_dir):
        fpath = os.path.join(downloads_dir, fname)
        if os.path.isfile(fpath):
            mtime = os.path.getmtime(fpath)
            if mtime >= task_start_epoch:
                ext = os.path.splitext(fname)[1].lower()
                size = os.path.getsize(fpath)
                new_files.append({"name": fname, "ext": ext, "size": size})

csv_xlsx = [f for f in new_files if f["ext"] in [".csv", ".xlsx", ".xls", ".tsv"]]
print(json.dumps({
    "new_files_count": len(new_files),
    "csv_xlsx_count": len(csv_xlsx),
    "file_names": [f["name"] for f in new_files[:10]],
    "total_size": sum(f["size"] for f in new_files)
}))
PYEOF
)

echo "Downloads result: $DOWNLOADS_RESULT"

# ---------------------------------------------------------------
# 4. Check analysis report file
# ---------------------------------------------------------------
echo "Checking dropout report file..."
REPORT_RESULT=$(python3 << 'PYEOF'
import os, json, re

report_path = "/home/ga/Desktop/dropout_report.txt"
task_start_epoch = int(open("/tmp/task_start_timestamp").read().strip() or "0")

result = {
    "exists": False,
    "length": 0,
    "content": "",
    "has_facility_count": False,
    "has_threshold_count": False,
    "has_facility_name": False,
    "has_trend_assessment": False
}

if os.path.exists(report_path):
    mtime = os.path.getmtime(report_path)
    if mtime >= task_start_epoch:
        result["exists"] = True
        content = open(report_path).read()
        result["length"] = len(content)
        result["content"] = content[:2000]  # First 2000 chars

        content_lower = content.lower()

        # (a) Has a number that could be the facility count
        result["has_facility_count"] = bool(re.search(r'\d+\s*(facilities|facility|health\s*facilit)', content_lower))

        # (b) Has a number related to threshold count (>50%)
        result["has_threshold_count"] = bool(re.search(r'\d+\s*(facilities|facility)', content_lower) and
                                             re.search(r'(exceed|above|over|greater|more than|>)\s*50', content_lower))

        # (c) Has a facility name (CHC, MCHP, CHP, Hospital pattern)
        result["has_facility_name"] = bool(re.search(r'(CHC|MCHP|CHP|Hospital|Govt|Government|clinic)', content, re.IGNORECASE))

        # (d) Has trend assessment
        result["has_trend_assessment"] = bool(re.search(r'(improv|worsen|increas|decreas|better|worse|stable|trend)', content_lower))

print(json.dumps(result))
PYEOF
)

echo "Report result: $REPORT_RESULT"

# ---------------------------------------------------------------
# 5. Get data element UIDs for formula cross-reference
# ---------------------------------------------------------------
echo "Getting data element UIDs for formula verification..."

# Fetch Penta1 UID
PENTA1_UID=$(curl -s -u admin:district "http://localhost:8080/api/dataElements?filter=name:ilike:penta1+doses&fields=id,name&paging=false" 2>/dev/null | \
python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for de in data.get('dataElements', []):
        if 'penta' in de['name'].lower() and '1' in de['name']:
            print(de['id'])
            break
except:
    pass
" 2>/dev/null)

# Fetch Fully Immunized UID
FULLY_IMM_UID=$(curl -s -u admin:district "http://localhost:8080/api/dataElements?filter=name:ilike:fully+immunized&fields=id,name&paging=false" 2>/dev/null | \
python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for de in data.get('dataElements', []):
        print(de['id'])
        break
except:
    pass
" 2>/dev/null)

DE_UIDS=$(python3 -c "
import json
result = {}
penta1 = '$PENTA1_UID'.strip()
fully = '$FULLY_IMM_UID'.strip()
if penta1:
    result['Penta1 doses given'] = penta1
if fully:
    result['Fully Immunized child'] = fully
print(json.dumps(result))
" 2>/dev/null || echo '{}')

echo "Data element UIDs: $DE_UIDS"

# ---------------------------------------------------------------
# Combine all results
# ---------------------------------------------------------------
cat > /tmp/district_immunization_completion_analysis_result.json << ENDJSON
{
    "task_start_iso": "$TASK_START_ISO",
    "indicator_check": $INDICATOR_RESULT,
    "visualization_check": $VIZ_RESULT,
    "downloads_check": $DOWNLOADS_RESULT,
    "report_check": $REPORT_RESULT,
    "data_element_uids": $DE_UIDS,
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

chmod 666 /tmp/district_immunization_completion_analysis_result.json 2>/dev/null || true
echo ""
echo "Result saved to /tmp/district_immunization_completion_analysis_result.json"
cat /tmp/district_immunization_completion_analysis_result.json
echo ""
echo "=== Export Complete ==="
