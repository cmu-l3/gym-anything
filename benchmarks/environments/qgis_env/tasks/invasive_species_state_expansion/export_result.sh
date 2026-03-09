#!/bin/bash
echo "=== Exporting invasive_species_state_expansion result ==="

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

take_screenshot /tmp/task_end_invasion.png

EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_GEOJSON="$EXPORT_DIR/invasion_status_by_state.geojson"
EXPECTED_CSV="$EXPORT_DIR/invasion_summary.csv"

TASK_START=$(cat /tmp/invasion_start_ts 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/invasion_initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")

FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_VALID="false"
FEATURE_COUNT=0
HAS_REQUIRED_FIELDS="false"
COUNT_ACCURACY=0
STATUS_ACCURACY=0
GT_STATE_COUNT=0
CSV_EXISTS="false"
CSV_VALID="false"

# Check for alt file names
if [ ! -f "$EXPECTED_GEOJSON" ]; then
    ALT=$(find "$EXPORT_DIR" -name "*invasion*" -o -name "*species*state*" 2>/dev/null | grep "\.geojson$" | head -1)
    [ -n "$ALT" ] && EXPECTED_GEOJSON="$ALT"
fi

if [ -f "$EXPECTED_GEOJSON" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$EXPECTED_GEOJSON" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && FILE_IS_NEW="true"

    ANALYSIS=$(python3 << PYEOF
import json, sys

gt_path = "/tmp/gt_invasion.json"
output_path = "$EXPECTED_GEOJSON"

try:
    with open(output_path) as f:
        data = json.load(f)
except Exception:
    print("valid=false"); print("feature_count=0"); print("has_required_fields=false")
    print("count_accuracy=0"); print("status_accuracy=0"); print("gt_state_count=0")
    sys.exit(0)

if data.get("type") != "FeatureCollection":
    print("valid=false"); print("feature_count=0"); print("has_required_fields=false")
    print("count_accuracy=0"); print("status_accuracy=0"); print("gt_state_count=0")
    sys.exit(0)

features = data.get("features", [])
feature_count = len(features)
print(f"valid=true")
print(f"feature_count={feature_count}")

required = {"count_2005_2012", "count_2016_2023", "pct_change", "invasion_status"}
found = set()
if features:
    sp = features[0].get("properties", {})
    found = {f for f in required if f in sp}
has_req = found == required
print(f"has_required_fields={'true' if has_req else 'false'}")

try:
    with open(gt_path) as f:
        gt = json.load(f)
    gt_stats = gt.get("state_stats", {})
    gt_state_count = gt.get("expected_state_count", 0)
    print(f"gt_state_count={gt_state_count}")
except Exception:
    print("gt_state_count=0"); print("count_accuracy=0"); print("status_accuracy=0")
    sys.exit(0)

# Build agent map by state name or postal
agent_map = {}
for feat in features:
    props = feat.get("properties", {})
    name = (props.get("name") or props.get("NAME") or "").strip()
    if name:
        agent_map[name] = props

total_gt = len(gt_stats)
correct_early = 0
correct_recent = 0
correct_status = 0

for state_name, gt_vals in gt_stats.items():
    if state_name not in agent_map:
        continue
    ap = agent_map[state_name]

    # Check count_2005_2012 accuracy (±1 tolerance)
    try:
        agent_early = int(ap.get("count_2005_2012", -1))
        if abs(agent_early - gt_vals["count_2005_2012"]) <= 1:
            correct_early += 1
    except (ValueError, TypeError):
        pass

    # Check count_2016_2023 accuracy (±1 tolerance)
    try:
        agent_recent = int(ap.get("count_2016_2023", -1))
        if abs(agent_recent - gt_vals["count_2016_2023"]) <= 1:
            correct_recent += 1
    except (ValueError, TypeError):
        pass

    # Check invasion_status
    agent_status = str(ap.get("invasion_status", "")).lower().strip().replace(" ", "_")
    gt_status = gt_vals["invasion_status"]
    # Re-derive from agent's own counts for fairness
    exp_status = gt_status
    try:
        ae = int(ap.get("count_2005_2012", 0))
        ar = int(ap.get("count_2016_2023", 0))
        if ar > ae and ae > 0: exp_status = "expanding"
        elif ae == 0 and ar > 0: exp_status = "new_invasion"
        elif ar <= ae and ae > 0 and ar > 0: exp_status = "established"
        elif ar == 0 and ae > 0: exp_status = "no_recent_activity"
    except (ValueError, TypeError):
        pass
    if agent_status == exp_status:
        correct_status += 1

count_acc = int(100 * (correct_early + correct_recent) / (2 * total_gt)) if total_gt > 0 else 0
status_acc = int(100 * correct_status / total_gt) if total_gt > 0 else 0
print(f"count_accuracy={count_acc}")
print(f"status_accuracy={status_acc}")
PYEOF
    )

    eval "$ANALYSIS"
    FILE_VALID="${valid:-false}"
    FEATURE_COUNT="${feature_count:-0}"
    HAS_REQUIRED_FIELDS="${has_required_fields:-false}"
    COUNT_ACCURACY="${count_accuracy:-0}"
    STATUS_ACCURACY="${status_accuracy:-0}"
    GT_STATE_COUNT="${gt_state_count:-0}"
fi

if [ -f "$EXPECTED_CSV" ]; then
    CSV_EXISTS="true"
    COLS=$(head -1 "$EXPECTED_CSV" 2>/dev/null || echo "")
    if echo "$COLS" | grep -qi "invasion_status" && echo "$COLS" | grep -qi "count\|state_count"; then
        CSV_VALID="true"
    fi
fi

if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

cat > /tmp/invasion_result.json << EOF
{
    "task_start": $TASK_START,
    "initial_export_count": $INITIAL_COUNT,
    "current_export_count": $CURRENT_COUNT,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_path": "$EXPECTED_GEOJSON",
    "file_valid_geojson": $FILE_VALID,
    "feature_count": $FEATURE_COUNT,
    "gt_state_count": $GT_STATE_COUNT,
    "has_required_fields": $HAS_REQUIRED_FIELDS,
    "count_accuracy": $COUNT_ACCURACY,
    "status_accuracy": $STATUS_ACCURACY,
    "csv_exists": $CSV_EXISTS,
    "csv_valid": $CSV_VALID,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/invasion_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/invasion_result.json
echo "=== Export Complete ==="
