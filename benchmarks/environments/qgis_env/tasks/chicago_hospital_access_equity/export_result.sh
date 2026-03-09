#!/bin/bash
echo "=== Exporting chicago_hospital_access_equity result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi

take_screenshot /tmp/task_end_hospital.png

EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_GEOJSON="$EXPORT_DIR/hospital_access_equity.geojson"
EXPECTED_CSV="$EXPORT_DIR/access_tier_summary.csv"

TASK_START=$(cat /tmp/hospital_start_ts 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/hospital_initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")

FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_VALID="false"
FEATURE_COUNT=0
HAS_REQUIRED_FIELDS="false"
NEAREST_DIST_ACCURACY=0
TIER_ACCURACY=0
GT_CA_COUNT=0
CSV_EXISTS="false"
CSV_VALID="false"

# Check for alt file names
if [ ! -f "$EXPECTED_GEOJSON" ]; then
    ALT=$(find "$EXPORT_DIR" -name "*hospital*access*" -o -name "*access*equity*" 2>/dev/null | grep "\.geojson$" | head -1)
    [ -n "$ALT" ] && EXPECTED_GEOJSON="$ALT"
fi

if [ -f "$EXPECTED_GEOJSON" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$EXPECTED_GEOJSON" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && FILE_IS_NEW="true"

    ANALYSIS=$(python3 << PYEOF
import json, sys, math

def haversine_km(lon1, lat1, lon2, lat2):
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
    return R * 2 * math.asin(math.sqrt(a))

gt_path = "/tmp/gt_hospital_access.json"
output_path = "$EXPECTED_GEOJSON"

try:
    with open(output_path) as f:
        data = json.load(f)
except Exception as e:
    print("valid=false"); print("feature_count=0"); print("has_required_fields=false")
    print("nearest_dist_accuracy=0"); print("tier_accuracy=0"); print("gt_ca_count=0")
    sys.exit(0)

if data.get("type") != "FeatureCollection":
    print("valid=false"); print("feature_count=0"); print("has_required_fields=false")
    print("nearest_dist_accuracy=0"); print("tier_accuracy=0"); print("gt_ca_count=0")
    sys.exit(0)

features = data.get("features", [])
feature_count = len(features)
print(f"valid=true")
print(f"feature_count={feature_count}")

required = {"nearest_hosp_km", "hosp_count_5km", "access_tier"}
found = set()
if features:
    sp = features[0].get("properties", {})
    found = {f for f in required if f in sp}
has_req = found == required
print(f"has_required_fields={'true' if has_req else 'false'}")

try:
    with open(gt_path) as f:
        gt = json.load(f)
    gt_stats = gt.get("community_stats", {})
    gt_ca_count = gt.get("expected_community_count", 0)
    print(f"gt_ca_count={gt_ca_count}")
except Exception:
    print("gt_ca_count=0"); print("nearest_dist_accuracy=0"); print("tier_accuracy=0")
    sys.exit(0)

# Match agent features to GT
agent_map = {}
for feat in features:
    props = feat.get("properties", {})
    name = (props.get("community") or props.get("COMMUNITY") or "").upper().strip()
    if name:
        agent_map[name] = props

correct_dist = 0
correct_tier = 0
total = len(gt_stats)

for ca_name, gt_vals in gt_stats.items():
    if ca_name not in agent_map:
        continue
    ap = agent_map[ca_name]
    gt_dist = gt_vals["nearest_hosp_km"]
    try:
        agent_dist = float(ap.get("nearest_hosp_km", -1))
        # Allow ±1 km tolerance (projected vs geographic distance differences)
        if abs(agent_dist - gt_dist) <= 1.0:
            correct_dist += 1
    except (ValueError, TypeError):
        pass

    gt_tier = gt_vals["access_tier"]
    agent_tier = str(ap.get("access_tier", "")).lower().strip()
    # Derive expected tier from agent's own hosp_count_5km
    exp_tier = gt_tier
    try:
        ac = int(ap.get("hosp_count_5km", -1))
        if ac >= 3: exp_tier = "high"
        elif ac >= 1: exp_tier = "medium"
        else: exp_tier = "low"
    except (ValueError, TypeError):
        pass
    if agent_tier == exp_tier:
        correct_tier += 1

da = int(100 * correct_dist / total) if total > 0 else 0
ta = int(100 * correct_tier / total) if total > 0 else 0
print(f"nearest_dist_accuracy={da}")
print(f"tier_accuracy={ta}")
PYEOF
    )

    eval "$ANALYSIS"
    FILE_VALID="${valid:-false}"
    FEATURE_COUNT="${feature_count:-0}"
    HAS_REQUIRED_FIELDS="${has_required_fields:-false}"
    NEAREST_DIST_ACCURACY="${nearest_dist_accuracy:-0}"
    TIER_ACCURACY="${tier_accuracy:-0}"
    GT_CA_COUNT="${gt_ca_count:-0}"
fi

# Check CSV output
if [ -f "$EXPECTED_CSV" ]; then
    CSV_EXISTS="true"
    # Check it has correct columns
    COLS=$(head -1 "$EXPECTED_CSV" 2>/dev/null || echo "")
    if echo "$COLS" | grep -qi "access_tier" && echo "$COLS" | grep -qi "community_count\|count\|pop"; then
        CSV_VALID="true"
    fi
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

cat > /tmp/hospital_access_result.json << EOF
{
    "task_start": $TASK_START,
    "initial_export_count": $INITIAL_COUNT,
    "current_export_count": $CURRENT_COUNT,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_path": "$EXPECTED_GEOJSON",
    "file_valid_geojson": $FILE_VALID,
    "feature_count": $FEATURE_COUNT,
    "gt_ca_count": $GT_CA_COUNT,
    "has_required_fields": $HAS_REQUIRED_FIELDS,
    "nearest_dist_accuracy": $NEAREST_DIST_ACCURACY,
    "tier_accuracy": $TIER_ACCURACY,
    "csv_exists": $CSV_EXISTS,
    "csv_valid": $CSV_VALID,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/hospital_access_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/hospital_access_result.json
echo "=== Export Complete ==="
