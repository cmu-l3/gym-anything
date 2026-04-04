#!/bin/bash
echo "=== Exporting urban_park_coverage_equity result ==="

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

take_screenshot /tmp/task_end_park.png

EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_GEOJSON="$EXPORT_DIR/park_coverage_by_tract.geojson"
EXPECTED_CSV="$EXPORT_DIR/greenspace_equity_summary.csv"

TASK_START=$(cat /tmp/park_coverage_start_ts 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/park_initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")

FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_VALID="false"
FEATURE_COUNT=0
HAS_REQUIRED_FIELDS="false"
PARK_PCT_ACCURACY=0
TIER_ACCURACY=0
USES_PROJECTED_CRS=0
GT_TRACT_COUNT=0
CSV_EXISTS="false"
CSV_VALID="false"

if [ ! -f "$EXPECTED_GEOJSON" ]; then
    ALT=$(find "$EXPORT_DIR" -name "*park*coverage*" -o -name "*greenspace*" 2>/dev/null | grep "\.geojson$" | head -1)
    [ -n "$ALT" ] && EXPECTED_GEOJSON="$ALT"
fi

if [ -f "$EXPECTED_GEOJSON" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$EXPECTED_GEOJSON" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && FILE_IS_NEW="true"

    ANALYSIS=$(python3 << PYEOF
import json, sys, math

gt_path = "/tmp/gt_park_coverage.json"
output_path = "$EXPECTED_GEOJSON"

try:
    with open(output_path) as f:
        data = json.load(f)
except Exception:
    print("valid=false"); print("feature_count=0"); print("has_required_fields=false")
    print("park_pct_accuracy=0"); print("tier_accuracy=0"); print("gt_tract_count=0")
    print("uses_projected_crs=0")
    sys.exit(0)

if data.get("type") != "FeatureCollection":
    print("valid=false"); print("feature_count=0"); print("has_required_fields=false")
    print("park_pct_accuracy=0"); print("tier_accuracy=0"); print("gt_tract_count=0")
    print("uses_projected_crs=0")
    sys.exit(0)

features = data.get("features", [])
feature_count = len(features)
print(f"valid=true")
print(f"feature_count={feature_count}")

required = {"park_area_sqm", "tract_area_sqm", "park_pct", "greenspace_tier"}
found = set()
if features:
    sp = features[0].get("properties", {})
    found = {f for f in required if f in sp}
has_req = found == required
print(f"has_required_fields={'true' if has_req else 'false'}")

try:
    with open(gt_path) as f:
        gt = json.load(f)
    gt_stats = gt.get("tract_stats", {})
    gt_tract_count = gt.get("expected_tract_count", 0)
    print(f"gt_tract_count={gt_tract_count}")
except Exception:
    print("gt_tract_count=0"); print("park_pct_accuracy=0"); print("tier_accuracy=0")
    print("uses_projected_crs=0")
    sys.exit(0)

# Build agent map by GEOID
agent_map = {}
for feat in features:
    props = feat.get("properties", {})
    geoid = props.get("GEOID", props.get("geoid", ""))
    if geoid:
        agent_map[geoid] = props

total_gt = len(gt_stats)
correct_park_pct = 0
correct_tier = 0
uses_projected = 0

# Check if areas look like square meters (> 1000) vs square degrees (< 1)
area_values = []
for feat in features[:20]:
    props = feat.get("properties", {})
    ta = props.get("tract_area_sqm")
    if ta:
        try:
            area_values.append(float(ta))
        except (ValueError, TypeError):
            pass

if area_values:
    avg_area = sum(area_values) / len(area_values)
    # Portland tracts in sq meters should be ~500,000 to 5,000,000
    # If in sq degrees they'd be ~0.0001 to 0.001
    if avg_area > 10000:
        uses_projected = 1
print(f"uses_projected_crs={uses_projected}")

for geoid, gt_vals in gt_stats.items():
    if geoid not in agent_map:
        continue
    ap = agent_map[geoid]
    gt_pct = gt_vals["park_pct"]
    try:
        agent_pct = float(ap.get("park_pct", -1))
        # Allow ±3 percentage points tolerance
        if abs(agent_pct - gt_pct) <= 3.0:
            correct_park_pct += 1
    except (ValueError, TypeError):
        pass

    gt_tier = gt_vals["greenspace_tier"]
    agent_tier = str(ap.get("greenspace_tier", "")).lower().strip()
    # Derive expected tier from agent's own park_pct
    exp_tier = gt_tier
    try:
        ap_pct = float(ap.get("park_pct", -1))
        if ap_pct >= 10.0: exp_tier = "adequate"
        elif ap_pct >= 5.0: exp_tier = "marginal"
        else: exp_tier = "deficient"
    except (ValueError, TypeError):
        pass
    if agent_tier == exp_tier:
        correct_tier += 1

ppa = int(100 * correct_park_pct / total_gt) if total_gt > 0 else 0
ta = int(100 * correct_tier / total_gt) if total_gt > 0 else 0
print(f"park_pct_accuracy={ppa}")
print(f"tier_accuracy={ta}")
PYEOF
    )

    eval "$ANALYSIS"
    FILE_VALID="${valid:-false}"
    FEATURE_COUNT="${feature_count:-0}"
    HAS_REQUIRED_FIELDS="${has_required_fields:-false}"
    PARK_PCT_ACCURACY="${park_pct_accuracy:-0}"
    TIER_ACCURACY="${tier_accuracy:-0}"
    GT_TRACT_COUNT="${gt_tract_count:-0}"
    USES_PROJECTED_CRS="${uses_projected_crs:-0}"
fi

if [ -f "$EXPECTED_CSV" ]; then
    CSV_EXISTS="true"
    COLS=$(head -1 "$EXPECTED_CSV" 2>/dev/null || echo "")
    if echo "$COLS" | grep -qi "greenspace_tier\|tier" && echo "$COLS" | grep -qi "tract_count\|count\|pop"; then
        CSV_VALID="true"
    fi
fi

if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

cat > /tmp/park_coverage_result.json << EOF
{
    "task_start": $TASK_START,
    "initial_export_count": $INITIAL_COUNT,
    "current_export_count": $CURRENT_COUNT,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_path": "$EXPECTED_GEOJSON",
    "file_valid_geojson": $FILE_VALID,
    "feature_count": $FEATURE_COUNT,
    "gt_tract_count": $GT_TRACT_COUNT,
    "has_required_fields": $HAS_REQUIRED_FIELDS,
    "park_pct_accuracy": $PARK_PCT_ACCURACY,
    "tier_accuracy": $TIER_ACCURACY,
    "uses_projected_crs": $USES_PROJECTED_CRS,
    "csv_exists": $CSV_EXISTS,
    "csv_valid": $CSV_VALID,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/park_coverage_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/park_coverage_result.json
echo "=== Export Complete ==="
