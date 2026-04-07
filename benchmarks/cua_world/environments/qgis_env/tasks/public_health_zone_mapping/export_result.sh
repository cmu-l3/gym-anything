#!/bin/bash
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' \t\n\r' || echo "0")

take_screenshot "/tmp/public_health_zone_final.png" || true

# Check for output file
OUTPUT_FILE="/home/ga/GIS_Data/exports/high_risk_zones.geojson"
OUTPUT_EXISTS="false"
FEATURE_COUNT=0
VALID_GEOJSON="false"
TRACT_IDS="[]"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"

    # Parse the output GeoJSON
    PARSED=$(python3 << 'PYEOF'
import json, sys, os

output_path = '/home/ga/GIS_Data/exports/high_risk_zones.geojson'

try:
    with open(output_path) as f:
        data = json.load(f)

    if data.get('type') != 'FeatureCollection':
        print(json.dumps({'valid': False, 'error': 'Not a FeatureCollection', 'count': 0, 'tract_ids': []}))
        sys.exit(0)

    features = data.get('features', [])
    tract_ids = []
    for feat in features:
        props = feat.get('properties', {})
        tid = props.get('tract_id') or props.get('TRACT_ID') or props.get('id', '')
        if tid:
            tract_ids.append(str(tid))

    print(json.dumps({
        'valid': True,
        'count': len(features),
        'tract_ids': tract_ids,
        'error': None
    }))

except Exception as e:
    print(json.dumps({'valid': False, 'error': str(e), 'count': 0, 'tract_ids': []}))
PYEOF
    )

    VALID_GEOJSON=$(echo "$PARSED" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('valid',False)).lower())" 2>/dev/null || echo "false")
    FEATURE_COUNT=$(echo "$PARSED" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('count',0))" 2>/dev/null || echo "0")
    TRACT_IDS=$(echo "$PARSED" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('tract_ids',[])))" 2>/dev/null || echo "[]")
    PARSE_ERROR=$(echo "$PARSED" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('error')))" 2>/dev/null || echo "null")
fi

# Also search for any alternative output files
ALT_OUTPUT=$(find /home/ga/GIS_Data -name "*.geojson" -newer /tmp/task_start_timestamp 2>/dev/null | grep -v census_tracts | head -1 || echo "")
if [ -n "$ALT_OUTPUT" ] && [ "$OUTPUT_EXISTS" = "false" ]; then
    OUTPUT_FILE="$ALT_OUTPUT"
    OUTPUT_EXISTS="true"
    PARSED=$(python3 -c "
import json
try:
    with open('${ALT_OUTPUT}') as f:
        d = json.load(f)
    feats = d.get('features', [])
    tids = [str(f.get('properties',{}).get('tract_id','')) for f in feats if f.get('properties',{}).get('tract_id')]
    print(json.dumps({'valid': d.get('type')=='FeatureCollection', 'count': len(feats), 'tract_ids': tids}))
except Exception as e:
    print(json.dumps({'valid': False, 'count': 0, 'tract_ids': [], 'error': str(e)}))
" 2>/dev/null || echo "{}")
    VALID_GEOJSON=$(echo "$PARSED" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d.get('valid',False)).lower())" 2>/dev/null || echo "false")
    FEATURE_COUNT=$(echo "$PARSED" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('count',0))" 2>/dev/null || echo "0")
    TRACT_IDS=$(echo "$PARSED" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('tract_ids',[])))" 2>/dev/null || echo "[]")
fi

cat > /tmp/public_health_zone_result.json << ENDJSON
{
  "task_start": ${TASK_START},
  "output_file": "${OUTPUT_FILE}",
  "output_file_exists": ${OUTPUT_EXISTS},
  "valid_geojson": ${VALID_GEOJSON},
  "feature_count": ${FEATURE_COUNT},
  "tract_ids_found": ${TRACT_IDS}
}
ENDJSON

chmod 666 /tmp/public_health_zone_result.json
echo "Export complete."
cat /tmp/public_health_zone_result.json
