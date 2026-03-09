#!/bin/bash
echo "=== Exporting seismic_risk_country_exposure result ==="

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

take_screenshot /tmp/task_end_seismic.png

EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_FILE="$EXPORT_DIR/country_seismic_exposure.geojson"

TASK_START=$(cat /tmp/seismic_start_ts 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/seismic_initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.geojson 2>/dev/null | wc -l || echo "0")

FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_VALID="false"
FEATURE_COUNT=0
HAS_REQUIRED_FIELDS="false"
FIELDS_FOUND=""
QUAKE_COUNT_ACCURACY="0"
RISK_TIER_ACCURACY="0"
GT_FEATURE_COUNT=0

if [ ! -f "$EXPECTED_FILE" ]; then
    ALT_FILE=$(find "$EXPORT_DIR" -name "*seismic*" -o -name "*country*exposure*" -o -name "*earthquake*country*" 2>/dev/null | grep "\.geojson$" | head -1)
    if [ -n "$ALT_FILE" ]; then
        EXPECTED_FILE="$ALT_FILE"
    fi
fi

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && FILE_IS_NEW="true"

    ANALYSIS=$(python3 << PYEOF
import json
import sys

gt_path = "/tmp/gt_seismic.json"
output_path = "$EXPECTED_FILE"

try:
    with open(output_path) as f:
        data = json.load(f)
except Exception as e:
    print(f"valid=false")
    print(f"feature_count=0")
    print(f"has_required_fields=false")
    print(f"fields_found=")
    print(f"quake_count_accuracy=0")
    print(f"risk_tier_accuracy=0")
    print(f"gt_feature_count=0")
    sys.exit(0)

if data.get("type") != "FeatureCollection":
    print(f"valid=false")
    print(f"feature_count=0")
    print(f"has_required_fields=false")
    print(f"fields_found=")
    print(f"quake_count_accuracy=0")
    print(f"risk_tier_accuracy=0")
    print(f"gt_feature_count=0")
    sys.exit(0)

features = data.get("features", [])
feature_count = len(features)
print(f"valid=true")
print(f"feature_count={feature_count}")

required_fields = {"quake_count", "mean_mag", "max_mag", "risk_tier"}
found_fields = set()
if features:
    sample_props = features[0].get("properties", {})
    found_fields = {f for f in required_fields if f in sample_props}

has_required = found_fields == required_fields
print(f"has_required_fields={'true' if has_required else 'false'}")
print(f"fields_found={'|'.join(sorted(found_fields))}")

# Load GT
try:
    with open(gt_path) as f:
        gt = json.load(f)
    gt_country_stats = gt.get("country_stats", {})
    gt_feature_count = gt.get("expected_feature_count", 0)
    print(f"gt_feature_count={gt_feature_count}")
except Exception:
    print(f"gt_feature_count=0")
    print(f"quake_count_accuracy=0")
    print(f"risk_tier_accuracy=0")
    sys.exit(0)

# Match agent features to GT by country name
matched = 0
correct_quake_count = 0
correct_risk_tier = 0

agent_country_map = {}
for feat in features:
    props = feat.get("properties", {})
    name = (props.get("ADMIN") or props.get("admin") or
            props.get("NAME") or props.get("name") or "")
    if name:
        agent_country_map[name] = props

for gt_name, gt_stats in gt_country_stats.items():
    if gt_name in agent_country_map:
        matched += 1
        agent_props = agent_country_map[gt_name]
        gt_count = gt_stats["quake_count"]
        agent_count = agent_props.get("quake_count", -1)
        try:
            agent_count = int(agent_count)
            # Allow tolerance of ±2 earthquakes per country
            if abs(agent_count - gt_count) <= 2:
                correct_quake_count += 1
        except (ValueError, TypeError):
            pass

        agent_tier = str(agent_props.get("risk_tier", "")).lower().strip()
        gt_tier = gt_stats["risk_tier"]
        # Accept risk_tier consistent with either GT count or agent's own count
        expected_tier = gt_tier
        if agent_props.get("quake_count") is not None:
            try:
                ac = int(agent_props["quake_count"])
                if ac < 5:
                    expected_tier = "low"
                elif ac < 15:
                    expected_tier = "medium"
                else:
                    expected_tier = "high"
            except (ValueError, TypeError):
                pass
        if agent_tier == expected_tier:
            correct_risk_tier += 1

total_gt = len(gt_country_stats)
if total_gt > 0:
    qca = int(100 * correct_quake_count / total_gt)
    rta = int(100 * correct_risk_tier / total_gt)
else:
    qca = 0
    rta = 0

print(f"quake_count_accuracy={qca}")
print(f"risk_tier_accuracy={rta}")
PYEOF
    )

    eval "$ANALYSIS"
    FILE_VALID="${valid:-false}"
    FEATURE_COUNT="${feature_count:-0}"
    HAS_REQUIRED_FIELDS="${has_required_fields:-false}"
    FIELDS_FOUND="${fields_found:-}"
    QUAKE_COUNT_ACCURACY="${quake_count_accuracy:-0}"
    RISK_TIER_ACCURACY="${risk_tier_accuracy:-0}"
    GT_FEATURE_COUNT="${gt_feature_count:-0}"
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

cat > /tmp/seismic_risk_result.json << EOF
{
    "task_start": $TASK_START,
    "initial_export_count": $INITIAL_COUNT,
    "current_export_count": $CURRENT_COUNT,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_path": "$EXPECTED_FILE",
    "file_valid_geojson": $FILE_VALID,
    "feature_count": $FEATURE_COUNT,
    "gt_feature_count": $GT_FEATURE_COUNT,
    "has_required_fields": $HAS_REQUIRED_FIELDS,
    "fields_found": "$FIELDS_FOUND",
    "quake_count_accuracy": $QUAKE_COUNT_ACCURACY,
    "risk_tier_accuracy": $RISK_TIER_ACCURACY,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/seismic_risk_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/seismic_risk_result.json
echo "=== Export Complete ==="
