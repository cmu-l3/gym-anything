#!/bin/bash
echo "=== Exporting emergency_medical_accessibility result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi

take_screenshot /tmp/task_end_accessibility.png

EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_GEOJSON="$EXPORT_DIR/community_accessibility.geojson"
EXPECTED_CSV="$EXPORT_DIR/priority_summary.csv"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Initialize result variables
FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_VALID="false"
FEATURE_COUNT=0
HAS_REQUIRED_FIELDS="false"
FIELDS_FOUND=""
FACILITY_DIST_ACCURACY=0
ROAD_DIST_ACCURACY=0
ISOLATION_ACCURACY=0
PRIORITY_ACCURACY=0
GT_COMMUNITY_COUNT=0
CSV_EXISTS="false"
CSV_VALID="false"

# Try alternate file names if expected file not found
if [ ! -f "$EXPECTED_GEOJSON" ]; then
    ALT_FILE=$(find "$EXPORT_DIR" -name "*accessibility*" -o -name "*community*" -o -name "*medical*" 2>/dev/null | grep "\.geojson$" | head -1)
    if [ -n "$ALT_FILE" ]; then
        EXPECTED_GEOJSON="$ALT_FILE"
    fi
fi

if [ -f "$EXPECTED_GEOJSON" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$EXPECTED_GEOJSON" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && FILE_IS_NEW="true"

    # Analyze the output GeoJSON
    ANALYSIS=$(python3 << PYEOF
import json, sys

output_path = "$EXPECTED_GEOJSON"
gt_path = "/tmp/gt_accessibility.json"

try:
    with open(output_path) as f:
        data = json.load(f)
except Exception as e:
    print("valid=false")
    print("feature_count=0")
    print("has_required_fields=false")
    print('fields_found=""')
    print("facility_dist_accuracy=0")
    print("road_dist_accuracy=0")
    print("isolation_accuracy=0")
    print("priority_accuracy=0")
    print("gt_community_count=0")
    sys.exit(0)

if data.get("type") != "FeatureCollection":
    print("valid=false")
    print("feature_count=0")
    print("has_required_fields=false")
    print('fields_found=""')
    print("facility_dist_accuracy=0")
    print("road_dist_accuracy=0")
    print("isolation_accuracy=0")
    print("priority_accuracy=0")
    print("gt_community_count=0")
    sys.exit(0)

features = data.get("features", [])
feature_count = len(features)
print(f"valid=true")
print(f"feature_count={feature_count}")

# Check required fields
required = {"name", "country", "population", "nearest_facility_km",
            "nearest_road_km", "isolation_score", "priority_class"}
found = set()
if features:
    props = features[0].get("properties", {})
    found = {f for f in required if f in props}

has_req = found == required
print(f"has_required_fields={'true' if has_req else 'false'}")
print(f'fields_found={len(found)}_of_{len(required)}')

# Load GT and compare
try:
    with open(gt_path) as f:
        gt = json.load(f)
    gt_stats = gt.get("community_stats", {})
    gt_count = gt.get("total_communities", 0)
    print(f"gt_community_count={gt_count}")
except Exception:
    print("gt_community_count=0")
    print("facility_dist_accuracy=0")
    print("road_dist_accuracy=0")
    print("isolation_accuracy=0")
    print("priority_accuracy=0")
    sys.exit(0)

# Match agent features to GT by name
agent_map = {}
for feat in features:
    props = feat.get("properties", {})
    name = props.get("name", "")
    if name:
        agent_map[name] = props

matched = 0
correct_facility = 0
correct_road = 0
correct_isolation = 0
correct_priority = 0

for gt_name, gt_vals in gt_stats.items():
    if gt_name not in agent_map:
        continue
    matched += 1
    agent = agent_map[gt_name]

    # nearest_facility_km: within +/- 3 km
    try:
        agent_fkm = float(agent.get("nearest_facility_km", -999))
        if abs(agent_fkm - gt_vals["nearest_facility_km"]) <= 3.0:
            correct_facility += 1
    except (ValueError, TypeError):
        pass

    # nearest_road_km: within +/- 3 km
    try:
        agent_rkm = float(agent.get("nearest_road_km", -999))
        if abs(agent_rkm - gt_vals["nearest_road_km"]) <= 3.0:
            correct_road += 1
    except (ValueError, TypeError):
        pass

    # isolation_score: within 15% relative tolerance
    try:
        agent_iso = float(agent.get("isolation_score", -999))
        gt_iso = gt_vals["isolation_score"]
        if gt_iso == 0:
            if abs(agent_iso) < 1.0:
                correct_isolation += 1
        elif abs(agent_iso - gt_iso) / max(abs(gt_iso), 0.01) <= 0.15:
            correct_isolation += 1
    except (ValueError, TypeError):
        pass

    # priority_class: exact match
    agent_pclass = str(agent.get("priority_class", "")).strip().lower()
    if agent_pclass == gt_vals["priority_class"]:
        correct_priority += 1

total = len(gt_stats)
if total > 0 and matched > 0:
    fda = int(100 * correct_facility / total)
    rda = int(100 * correct_road / total)
    isa = int(100 * correct_isolation / total)
    pa = int(100 * correct_priority / total)
else:
    fda = rda = isa = pa = 0

print(f"facility_dist_accuracy={fda}")
print(f"road_dist_accuracy={rda}")
print(f"isolation_accuracy={isa}")
print(f"priority_accuracy={pa}")
PYEOF
    )

    eval "$ANALYSIS"
    FILE_VALID="${valid:-false}"
    FEATURE_COUNT="${feature_count:-0}"
    HAS_REQUIRED_FIELDS="${has_required_fields:-false}"
    FIELDS_FOUND="${fields_found:-}"
    FACILITY_DIST_ACCURACY="${facility_dist_accuracy:-0}"
    ROAD_DIST_ACCURACY="${road_dist_accuracy:-0}"
    ISOLATION_ACCURACY="${isolation_accuracy:-0}"
    PRIORITY_ACCURACY="${priority_accuracy:-0}"
    GT_COMMUNITY_COUNT="${gt_community_count:-0}"
fi

# Check CSV
if [ -f "$EXPECTED_CSV" ]; then
    CSV_EXISTS="true"
    CSV_HEADER=$(head -1 "$EXPECTED_CSV" 2>/dev/null || echo "")
    if echo "$CSV_HEADER" | grep -qi "priority_class" && \
       echo "$CSV_HEADER" | grep -qi "community_count\|count"; then
        CSV_VALID="true"
    fi
elif [ -f "$EXPORT_DIR/priority_summary.csv" ]; then
    CSV_EXISTS="true"
    CSV_HEADER=$(head -1 "$EXPORT_DIR/priority_summary.csv" 2>/dev/null || echo "")
    if echo "$CSV_HEADER" | grep -qi "priority_class"; then
        CSV_VALID="true"
    fi
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# Write result JSON
cat > /tmp/accessibility_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_path": "$EXPECTED_GEOJSON",
    "file_valid_geojson": $FILE_VALID,
    "feature_count": $FEATURE_COUNT,
    "gt_community_count": $GT_COMMUNITY_COUNT,
    "has_required_fields": $HAS_REQUIRED_FIELDS,
    "fields_found": "$FIELDS_FOUND",
    "facility_dist_accuracy": $FACILITY_DIST_ACCURACY,
    "road_dist_accuracy": $ROAD_DIST_ACCURACY,
    "isolation_accuracy": $ISOLATION_ACCURACY,
    "priority_accuracy": $PRIORITY_ACCURACY,
    "csv_exists": $CSV_EXISTS,
    "csv_valid": $CSV_VALID,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/accessibility_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/accessibility_result.json
echo "=== Export Complete ==="
