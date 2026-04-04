#!/bin/bash
# Export result for commercial_pv_battery_demand_charge task
echo "=== Exporting Commercial PV+Battery Demand Charge Result ==="

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/SAM_Projects/Denver_Commercial_Battery_Analysis.json"

# Take end screenshot
DISPLAY=:1 import -window root /tmp/pv_battery_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/pv_battery_end_screenshot.png 2>/dev/null || true

# Check output file existence and freshness
FILE_EXISTS=false
FILE_MODIFIED=false
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED=true
    fi
fi

# Anti-bypass: detect Python scripts using Battery PySAM module
BATTERY_MODEL_USED=false
PYTHON_RAN=false

NEW_PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null | head -20)
if [ -n "$NEW_PY_FILES" ]; then
    PYTHON_RAN=true
    BATT_CHECK=$(echo "$NEW_PY_FILES" | xargs grep -l \
        "Battery\|BatteryNone\|batt_kwh\|batt_kw\|batt_dispatch\|demand_charge\|Utilityrate\|ur_dc_" \
        2>/dev/null | head -5)
    if [ -n "$BATT_CHECK" ]; then
        BATTERY_MODEL_USED=true
    fi
fi

TMP_PY=$(find /tmp /root -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null | head -10)
if [ -n "$TMP_PY" ]; then
    PYTHON_RAN=true
    BATT_TMP=$(echo "$TMP_PY" | xargs grep -l \
        "Battery\|batt_kwh\|demand_charge\|Utilityrate" \
        2>/dev/null | head -3)
    if [ -n "$BATT_TMP" ]; then
        BATTERY_MODEL_USED=true
    fi
fi

# Parse output JSON
NUM_CONFIGS="0"
MIN_PAYBACK="0"
MAX_NPV="0"
FIRST_DEMAND_SAVINGS="0"
OPTIMAL_CONFIG=""
HAS_CONFIGS=false

if [ "$FILE_EXISTS" = "true" ]; then
    NUM_CONFIGS=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    configs = None
    for key in ['configurations', 'configs', 'results']:
        if key in d and isinstance(d[key], list):
            configs = d[key]
            break
    print(len(configs) if configs else 0)
except:
    print(0)
" 2>/dev/null || echo "0")

    MIN_PAYBACK=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    configs = None
    for key in ['configurations', 'configs', 'results']:
        if key in d and isinstance(d[key], list):
            configs = d[key]
            break
    if not configs:
        print(0)
        sys.exit(0)
    paybacks = []
    for cfg in configs:
        if isinstance(cfg, dict):
            for k in ['simple_payback_years', 'payback_years', 'payback', 'simple_payback']:
                v = cfg.get(k)
                if v is not None and isinstance(v, (int, float)) and v > 0:
                    paybacks.append(float(v))
                    break
    print(min(paybacks) if paybacks else 0)
except:
    print(0)
" 2>/dev/null || echo "0")

    MAX_NPV=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    configs = None
    for key in ['configurations', 'configs', 'results']:
        if key in d and isinstance(d[key], list):
            configs = d[key]
            break
    if not configs:
        print(0)
        sys.exit(0)
    npvs = []
    for cfg in configs:
        if isinstance(cfg, dict):
            for k in ['npv_25yr_usd', 'npv_usd', 'npv', 'NPV']:
                v = cfg.get(k)
                if v is not None and isinstance(v, (int, float)):
                    npvs.append(float(v))
                    break
    print(max(npvs) if npvs else 0)
except:
    print(0)
" 2>/dev/null || echo "0")

    FIRST_DEMAND_SAVINGS=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    configs = None
    for key in ['configurations', 'configs', 'results']:
        if key in d and isinstance(d[key], list):
            configs = d[key]
            break
    if not configs or len(configs) == 0:
        print(0)
        sys.exit(0)
    cfg = configs[0]
    if isinstance(cfg, dict):
        for k in ['annual_demand_charge_savings_usd', 'demand_savings', 'demand_charge_savings']:
            v = cfg.get(k)
            if v is not None and isinstance(v, (int, float)):
                print(float(v))
                sys.exit(0)
    print(0)
except:
    print(0)
" 2>/dev/null || echo "0")

    OPTIMAL_CONFIG=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    for k in ['optimal_configuration', 'best_configuration', 'optimal', 'recommended']:
        v = d.get(k)
        if v and isinstance(v, str) and len(v) > 2:
            print(v[:80])
            sys.exit(0)
    print('')
except:
    print('')
" 2>/dev/null || echo "")

    if [ "$NUM_CONFIGS" -ge 2 ] 2>/dev/null; then
        HAS_CONFIGS=true
    fi
fi

# Escape optimal config for JSON
OPTIMAL_CONFIG_ESC=$(echo "$OPTIMAL_CONFIG" | sed 's/"/\\"/g')

cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "battery_model_used": $BATTERY_MODEL_USED,
    "python_ran": $PYTHON_RAN,
    "num_configs": $NUM_CONFIGS,
    "has_configs": $HAS_CONFIGS,
    "min_payback": $MIN_PAYBACK,
    "max_npv": $MAX_NPV,
    "first_demand_savings": $FIRST_DEMAND_SAVINGS,
    "optimal_config": "$OPTIMAL_CONFIG_ESC",
    "task_start": $TASK_START
}
EOF

echo "=== Export Complete ==="
echo "Result written to /tmp/task_result.json"
cat /tmp/task_result.json
