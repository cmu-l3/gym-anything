#!/bin/bash
# Export script for Custom Facility Attributes task

echo "=== Exporting Custom Facility Attributes Result ==="

source /workspace/scripts/task_utils.sh

# Helper definitions
if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# 1. Capture final state screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Check for the existence of the created attributes
echo "Querying Attributes..."

# Query Attribute 1: Generator Functional
ATTR1_JSON=$(dhis2_api "attributes?filter=name:eq:Generator+Functional&fields=id,name,valueType,organisationUnitAttribute&paging=false" 2>/dev/null)
echo "Attr1 raw: $ATTR1_JSON"

# Query Attribute 2: Distance...
ATTR2_JSON=$(dhis2_api "attributes?filter=name:eq:Distance+to+District+Office+(km)&fields=id,name,valueType,organisationUnitAttribute&paging=false" 2>/dev/null)
echo "Attr2 raw: $ATTR2_JSON"

# 3. Check the Organisation Unit for values
# We need the facility ID for 'Bo Govt Hospital'
echo "Querying Facility..."
FACILITY_JSON=$(dhis2_api "organisationUnits?filter=name:eq:Bo+Govt+Hospital&fields=id,name,attributeValues[attribute[id],value]&paging=false" 2>/dev/null)
echo "Facility raw: $FACILITY_JSON"

# 4. Construct JSON result
# Python script to parse the messy API responses and combine them
python3 << EOF > /tmp/custom_facility_attributes_result.json
import json
import sys

def parse_attr_response(json_str):
    try:
        data = json.loads(json_str)
        attrs = data.get('attributes', [])
        if attrs:
            return attrs[0]
        return None
    except:
        return None

try:
    attr1_raw = '$ATTR1_JSON'
    attr2_raw = '$ATTR2_JSON'
    facility_raw = '$FACILITY_JSON'
    
    attr1 = parse_attr_response(attr1_raw)
    attr2 = parse_attr_response(attr2_raw)
    
    facility_data = {}
    try:
        f_data = json.loads(facility_raw)
        if f_data.get('organisationUnits'):
            facility_data = f_data['organisationUnits'][0]
    except:
        pass

    result = {
        "attr1_found": attr1 is not None,
        "attr1_data": attr1,
        "attr2_found": attr2 is not None,
        "attr2_data": attr2,
        "facility_found": bool(facility_data),
        "facility_data": facility_data,
        "task_timestamp": "$(date +%s)"
    }
    
    print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

echo "Result JSON generated at /tmp/custom_facility_attributes_result.json"
cat /tmp/custom_facility_attributes_result.json
echo "=== Export Complete ==="