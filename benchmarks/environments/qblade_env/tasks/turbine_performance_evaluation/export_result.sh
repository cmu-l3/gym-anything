#!/bin/bash
echo "=== Exporting turbine_performance_evaluation Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

PROJECT_DIR="/home/ga/Documents/projects"
BEM_FILE="$PROJECT_DIR/nrel5mw_bem_results.txt"
REPORT_FILE="$PROJECT_DIR/nrel5mw_report.txt"
RESULT_FILE="/tmp/task_result.json"

# === Analyze BEM results file ===
BEM_EXISTS="false"
BEM_LINES=0
BEM_HAS_DATA="false"
BEM_DATA_POINTS=0
BEM_HAS_CP="false"
BEM_HAS_TSR="false"

if [ -f "$BEM_FILE" ]; then
    BEM_EXISTS="true"
    BEM_LINES=$(wc -l < "$BEM_FILE")

    # Count multi-column numeric data rows
    BEM_DATA_POINTS=$(grep -cE '^[[:space:]]*[0-9]+\.?[0-9]*[[:space:]]+-?[0-9]+\.[0-9]+' "$BEM_FILE" 2>/dev/null || echo "0")
    if [ "$BEM_DATA_POINTS" -gt 0 ]; then
        BEM_HAS_DATA="true"
    fi

    # Check for Cp-related keywords (case-insensitive)
    if grep -qiE 'Cp|power.?coeff|C_P' "$BEM_FILE" 2>/dev/null; then
        BEM_HAS_CP="true"
    fi

    # Check for TSR-related keywords
    if grep -qiE 'TSR|tip.?speed|lambda|tip_speed_ratio' "$BEM_FILE" 2>/dev/null; then
        BEM_HAS_TSR="true"
    fi
fi

# === Analyze report file ===
REPORT_EXISTS="false"
REPORT_LINES=0
REPORT_HAS_OPTIMAL_TSR="false"
REPORT_HAS_MAX_CP="false"
REPORT_TSR_VALUE=""
REPORT_CP_VALUE=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_LINES=$(wc -l < "$REPORT_FILE")

    # Use Python for robust extraction of numeric values from the report
    python3 << 'PYEOF' > /tmp/report_analysis.json 2>/dev/null
import json, re

with open("/home/ga/Documents/projects/nrel5mw_report.txt") as f:
    content = f.read().lower()

# Look for TSR value (number between 1 and 15 near "tsr" or "tip speed" keywords)
tsr_val = ""
has_tsr = False
tsr_patterns = [
    r'(?:optimal|max|best|peak)\s*tsr[:\s=]*(\d+\.?\d*)',
    r'tsr[:\s=]*(\d+\.?\d*)',
    r'tip.?speed.?ratio[:\s=]*(\d+\.?\d*)',
    r'lambda[:\s=]*(\d+\.?\d*)',
]
for pat in tsr_patterns:
    m = re.search(pat, content)
    if m:
        val = float(m.group(1))
        if 1 <= val <= 15:
            tsr_val = str(val)
            has_tsr = True
            break

# Look for Cp value (number between 0.1 and 0.6 near "cp" or "power coeff" keywords)
cp_val = ""
has_cp = False
cp_patterns = [
    r'(?:max|maximum|peak)\s*cp[:\s=]*(\d+\.?\d*)',
    r'cp[:\s=]*(\d+\.?\d*)',
    r'power.?coeff\w*[:\s=]*(\d+\.?\d*)',
]
for pat in cp_patterns:
    m = re.search(pat, content)
    if m:
        val = float(m.group(1))
        if 0.1 <= val <= 0.6:
            cp_val = str(val)
            has_cp = True
            break

result = {
    "has_optimal_tsr": has_tsr,
    "tsr_value": tsr_val,
    "has_max_cp": has_cp,
    "cp_value": cp_val
}
with open("/tmp/report_analysis.json", "w") as f:
    json.dump(result, f)
PYEOF

    if [ -f /tmp/report_analysis.json ]; then
        REPORT_HAS_OPTIMAL_TSR=$(python3 -c "import json; d=json.load(open('/tmp/report_analysis.json')); print(str(d['has_optimal_tsr']).lower())" 2>/dev/null || echo "false")
        REPORT_HAS_MAX_CP=$(python3 -c "import json; d=json.load(open('/tmp/report_analysis.json')); print(str(d['has_max_cp']).lower())" 2>/dev/null || echo "false")
        REPORT_TSR_VALUE=$(python3 -c "import json; d=json.load(open('/tmp/report_analysis.json')); print(d['tsr_value'])" 2>/dev/null || echo "")
        REPORT_CP_VALUE=$(python3 -c "import json; d=json.load(open('/tmp/report_analysis.json')); print(d['cp_value'])" 2>/dev/null || echo "")
    fi
fi

# Check QBlade running
QBLADE_RUNNING="false"
if is_qblade_running; then
    QBLADE_RUNNING="true"
fi

# Baseline
INITIAL_TXT_COUNT=$(cat /tmp/initial_txt_count 2>/dev/null || echo "0")

cat > "$RESULT_FILE" << EOF
{
    "bem_file": {
        "exists": $BEM_EXISTS,
        "lines": $BEM_LINES,
        "has_data": $BEM_HAS_DATA,
        "data_points": $BEM_DATA_POINTS,
        "has_cp": $BEM_HAS_CP,
        "has_tsr": $BEM_HAS_TSR
    },
    "report_file": {
        "exists": $REPORT_EXISTS,
        "lines": $REPORT_LINES,
        "has_optimal_tsr": $REPORT_HAS_OPTIMAL_TSR,
        "has_max_cp": $REPORT_HAS_MAX_CP,
        "tsr_value": "$REPORT_TSR_VALUE",
        "cp_value": "$REPORT_CP_VALUE"
    },
    "initial_txt_count": $INITIAL_TXT_COUNT,
    "qblade_running": $QBLADE_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="
