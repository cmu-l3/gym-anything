#!/bin/bash
echo "=== Exporting air_quality_monitor_coverage result ==="

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

take_screenshot /tmp/task_end_aq.png

EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_GEOJSON="$EXPORT_DIR/pm25_coverage_gaps.geojson"
EXPECTED_CSV="$EXPORT_DIR/monitoring_coverage_report.csv"

TASK_START=$(cat /tmp/aq_coverage_start_ts 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/aq_initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")

FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_VALID="false"
FEATURE_COUNT=0
HAS_REQUIRED_FIELDS="false"
MONITOR_COUNT_ACCURACY=0
COVERAGE_STATUS_ACCURACY=0
USES_PROJECTED_CRS=0
GT_COUNTY_COUNT=0
CSV_EXISTS="false"
CSV_VALID="false"

if [ ! -f "$EXPECTED_GEOJSON" ]; then
    ALT=$(find "$EXPORT_DIR" -name "*pm25*" -o -name "*air*quality*" -o -name "*monitor*coverage*" 2>/dev/null | grep "\.geojson$" | head -1)
    [ -n "$ALT" ] && EXPECTED_GEOJSON="$ALT"
fi

if [ -f "$EXPECTED_GEOJSON" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$EXPECTED_GEOJSON" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && FILE_IS_NEW="true"

    ANALYSIS=$(python3 << PYEOF
import json, sys, math

gt_path = "/tmp/gt_aq_coverage.json"
output_path = "$EXPECTED_GEOJSON"

try:
    with open(output_path) as f:
        data = json.load(f)
except Exception:
    print("valid=false"); print("feature_count=0"); print("has_required_fields=false")
    print("monitor_count_accuracy=0"); print("coverage_status_accuracy=0")
    print("gt_county_count=0"); print("uses_projected_crs=0")
    sys.exit(0)

if data.get("type") != "FeatureCollection":
    print("valid=false"); print("feature_count=0"); print("has_required_fields=false")
    print("monitor_count_accuracy=0"); print("coverage_status_accuracy=0")
    print("gt_county_count=0"); print("uses_projected_crs=0")
    sys.exit(0)

features = data.get("features", [])
feature_count = len(features)
print(f"valid=true")
print(f"feature_count={feature_count}")

required = {"monitor_count", "nearest_monitor_km", "coverage_status", "monitoring_density"}
found = set()
if features:
    sp = features[0].get("properties", {})
    found = {f for f in required if f in sp}
has_req = found == required
print(f"has_required_fields={'true' if has_req else 'false'}")

try:
    with open(gt_path) as f:
        gt = json.load(f)
    gt_stats = gt.get("county_stats", {})
    gt_county_count = gt.get("expected_county_count", 0)
    print(f"gt_county_count={gt_county_count}")
except Exception:
    print("gt_county_count=0"); print("monitor_count_accuracy=0")
    print("coverage_status_accuracy=0"); print("uses_projected_crs=0")
    sys.exit(0)

# Build agent map by county name
agent_map = {}
for feat in features:
    props = feat.get("properties", {})
    name = (props.get("NAME") or props.get("name") or props.get("county_name") or "").strip()
    if name:
        agent_map[name] = props

# Check if monitoring_density values suggest projected CRS (areas in km²)
density_values = []
count_values = []
for feat in features[:20]:
    props = feat.get("properties", {})
    d = props.get("monitoring_density")
    mc = props.get("monitor_count")
    if d is not None:
        try:
            density_values.append(float(d))
        except (ValueError, TypeError):
            pass
    if mc is not None:
        try:
            count_values.append(int(mc))
        except (ValueError, TypeError):
            pass

# monitoring_density should be tiny numbers like 0.0001-0.001 for km²
# If computed with sq degrees it would be much larger
uses_projected = 0
if density_values:
    has_nonzero = [v for v in density_values if v > 0]
    if has_nonzero:
        avg_density = sum(has_nonzero) / len(has_nonzero)
        # km²: ~0.00001 to 0.001 monitors/km²
        # sq_degrees: much larger or inconsistent
        if avg_density < 0.1:
            uses_projected = 1
    elif count_values and sum(count_values) == 0:
        pass  # All zero count - maybe gap counties; give benefit
    else:
        uses_projected = 1  # If density all zero but counts nonzero, something is wrong
print(f"uses_projected_crs={uses_projected}")

total_gt = len(gt_stats)
correct_count = 0
correct_status = 0

for county_name, gt_vals in gt_stats.items():
    if county_name not in agent_map:
        continue
    ap = agent_map[county_name]

    # Check monitor_count accuracy (±1 tolerance)
    try:
        agent_mc = int(ap.get("monitor_count", -1))
        if abs(agent_mc - gt_vals["monitor_count"]) <= 1:
            correct_count += 1
    except (ValueError, TypeError):
        pass

    # Check coverage_status
    gt_status = gt_vals["coverage_status"]
    agent_status = str(ap.get("coverage_status", "")).lower().strip()
    # Derive from agent's own monitor_count
    exp_status = gt_status
    try:
        amc = int(ap.get("monitor_count", 0))
        exp_status = "monitored" if amc >= 1 else "gap"
    except (ValueError, TypeError):
        pass
    if agent_status == exp_status:
        correct_status += 1

mca = int(100 * correct_count / total_gt) if total_gt > 0 else 0
csa = int(100 * correct_status / total_gt) if total_gt > 0 else 0
print(f"monitor_count_accuracy={mca}")
print(f"coverage_status_accuracy={csa}")
PYEOF
    )

    eval "$ANALYSIS"
    FILE_VALID="${valid:-false}"
    FEATURE_COUNT="${feature_count:-0}"
    HAS_REQUIRED_FIELDS="${has_required_fields:-false}"
    MONITOR_COUNT_ACCURACY="${monitor_count_accuracy:-0}"
    COVERAGE_STATUS_ACCURACY="${coverage_status_accuracy:-0}"
    GT_COUNTY_COUNT="${gt_county_count:-0}"
    USES_PROJECTED_CRS="${uses_projected_crs:-0}"
fi

if [ -f "$EXPECTED_CSV" ]; then
    CSV_EXISTS="true"
    COLS=$(head -1 "$EXPECTED_CSV" 2>/dev/null || echo "")
    if echo "$COLS" | grep -qi "county_name\|county" && echo "$COLS" | grep -qi "monitor_count\|coverage"; then
        CSV_VALID="true"
    fi
fi

if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

cat > /tmp/aq_coverage_result.json << EOF
{
    "task_start": $TASK_START,
    "initial_export_count": $INITIAL_COUNT,
    "current_export_count": $CURRENT_COUNT,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_path": "$EXPECTED_GEOJSON",
    "file_valid_geojson": $FILE_VALID,
    "feature_count": $FEATURE_COUNT,
    "gt_county_count": $GT_COUNTY_COUNT,
    "has_required_fields": $HAS_REQUIRED_FIELDS,
    "monitor_count_accuracy": $MONITOR_COUNT_ACCURACY,
    "coverage_status_accuracy": $COVERAGE_STATUS_ACCURACY,
    "uses_projected_crs": $USES_PROJECTED_CRS,
    "csv_exists": $CSV_EXISTS,
    "csv_valid": $CSV_VALID,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/aq_coverage_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/aq_coverage_result.json
echo "=== Export Complete ==="
