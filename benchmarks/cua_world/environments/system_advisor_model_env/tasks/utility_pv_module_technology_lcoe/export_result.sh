#!/bin/bash
# Export result for utility_pv_module_technology_lcoe task
echo "=== Exporting Utility PV Module Technology LCOE Result ==="

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/SAM_Projects/Daggett_Module_Technology_LCOE.json"

# Take end screenshot
DISPLAY=:1 import -window root /tmp/pv_module_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/pv_module_end_screenshot.png 2>/dev/null || true

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

# Anti-bypass: detect Python using Pvsamv1 (detailed PV model)
PVSAMV1_USED=false
PYTHON_RAN=false

NEW_PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null | head -20)
if [ -n "$NEW_PY_FILES" ]; then
    PYTHON_RAN=true
    PVSAMV1_CHECK=$(echo "$NEW_PY_FILES" | xargs grep -l \
        "Pvsamv1\|pvsamv1\|CECPerformance\|cec_v_mp_ref\|cec_i_mp_ref\|module_model\|SingleOwner\|FlatPlatePV" \
        2>/dev/null | head -5)
    if [ -n "$PVSAMV1_CHECK" ]; then
        PVSAMV1_USED=true
    fi
fi

TMP_PY=$(find /tmp /root -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null | head -10)
if [ -n "$TMP_PY" ]; then
    PYTHON_RAN=true
    PVSAMV1_TMP=$(echo "$TMP_PY" | xargs grep -l \
        "Pvsamv1\|pvsamv1\|cec_v_mp_ref\|module_model" \
        2>/dev/null | head -3)
    if [ -n "$PVSAMV1_TMP" ]; then
        PVSAMV1_USED=true
    fi
fi

# Parse output JSON
NUM_TECHS="0"
MIN_LCOE="0"
MAX_CF="0"
FIRST_AEP="0"
OPTIMAL_TECH=""
HAS_CONFIGS=false

if [ "$FILE_EXISTS" = "true" ]; then
    NUM_TECHS=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    configs = None
    for key in ['configurations', 'configs', 'results', 'technologies']:
        if key in d and isinstance(d[key], list):
            configs = d[key]
            break
    print(len(configs) if configs else 0)
except:
    print(0)
" 2>/dev/null || echo "0")

    MIN_LCOE=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    configs = None
    for key in ['configurations', 'configs', 'results', 'technologies']:
        if key in d and isinstance(d[key], list):
            configs = d[key]
            break
    if not configs:
        print(0); sys.exit(0)
    lcoes = []
    for cfg in configs:
        if isinstance(cfg, dict):
            for k in ['lcoe_real_usd_per_mwh', 'lcoe_real', 'lcoe', 'LCOE']:
                v = cfg.get(k)
                if v and isinstance(v, (int, float)) and v > 0:
                    # If in cents/kWh, convert to $/MWh (* 10)
                    val = float(v)
                    if val < 5:  # likely cents/kWh
                        val *= 10
                    lcoes.append(val)
                    break
    print(min(lcoes) if lcoes else 0)
except:
    print(0)
" 2>/dev/null || echo "0")

    MAX_CF=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    configs = None
    for key in ['configurations', 'configs', 'results', 'technologies']:
        if key in d and isinstance(d[key], list):
            configs = d[key]
            break
    if not configs:
        print(0); sys.exit(0)
    cfs = []
    for cfg in configs:
        if isinstance(cfg, dict):
            for k in ['capacity_factor_pct', 'capacity_factor', 'cf', 'CF']:
                v = cfg.get(k)
                if v and isinstance(v, (int, float)) and v > 0:
                    cfs.append(float(v))
                    break
    print(max(cfs) if cfs else 0)
except:
    print(0)
" 2>/dev/null || echo "0")

    FIRST_AEP=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    configs = None
    for key in ['configurations', 'configs', 'results', 'technologies']:
        if key in d and isinstance(d[key], list):
            configs = d[key]
            break
    if not configs or len(configs) == 0:
        print(0); sys.exit(0)
    cfg = configs[0]
    if isinstance(cfg, dict):
        for k in ['annual_energy_year1_mwh', 'annual_energy_mwh', 'annual_energy', 'aep_mwh']:
            v = cfg.get(k)
            if v and isinstance(v, (int, float)) and v > 0:
                val = float(v)
                if val > 10000000:  # likely kWh
                    val = val / 1000
                print(val); sys.exit(0)
    print(0)
except:
    print(0)
" 2>/dev/null || echo "0")

    OPTIMAL_TECH=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    for k in ['optimal_technology', 'best_technology', 'optimal_tech', 'optimal']:
        v = d.get(k)
        if v and isinstance(v, str) and len(v) > 2:
            print(v[:80]); sys.exit(0)
    print('')
except:
    print('')
" 2>/dev/null || echo "")

    if [ "$NUM_TECHS" -ge 2 ] 2>/dev/null; then
        HAS_CONFIGS=true
    fi
fi

OPTIMAL_TECH_ESC=$(echo "$OPTIMAL_TECH" | sed 's/"/\\"/g')

cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "pvsamv1_used": $PVSAMV1_USED,
    "python_ran": $PYTHON_RAN,
    "num_technologies": $NUM_TECHS,
    "has_configs": $HAS_CONFIGS,
    "min_lcoe": $MIN_LCOE,
    "max_cf": $MAX_CF,
    "first_aep": $FIRST_AEP,
    "optimal_technology": "$OPTIMAL_TECH_ESC",
    "task_start": $TASK_START
}
EOF

echo "=== Export Complete ==="
echo "Result written to /tmp/task_result.json"
cat /tmp/task_result.json
