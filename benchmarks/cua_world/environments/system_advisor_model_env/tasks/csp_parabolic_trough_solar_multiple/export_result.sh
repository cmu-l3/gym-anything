#!/bin/bash
# Export result for csp_parabolic_trough_solar_multiple task
echo "=== Exporting CSP Solar Multiple Task Result ==="

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/SAM_Projects/Daggett_CSP_SM_Analysis.json"

# Take end screenshot
DISPLAY=:1 import -window root /tmp/csp_sm_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/csp_sm_end_screenshot.png 2>/dev/null || true

# Check if output file exists and was created during task
FILE_EXISTS=false
FILE_MODIFIED=false
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED=true
    fi
fi

# Anti-bypass: check if Python script using CSP PySAM modules was run
CSP_MODEL_USED=false
PYTHON_RAN=false

# Find Python files newer than task start that use CSP-related PySAM imports
NEW_PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null | head -20)
if [ -n "$NEW_PY_FILES" ]; then
    PYTHON_RAN=true
    # Check for CSP-specific PySAM imports
    CSP_CHECK=$(echo "$NEW_PY_FILES" | xargs grep -l \
        "TroughPhysical\|EmpiricalTrough\|trough\|Trough\|CSP\|csp\|solar_mult\|tshours\|TES\|thermal_storage" \
        2>/dev/null | head -5)
    if [ -n "$CSP_CHECK" ]; then
        CSP_MODEL_USED=true
    fi
fi

# Also check /tmp and /root for Python scripts
TMP_PY=$(find /tmp /root -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null | head -10)
if [ -n "$TMP_PY" ]; then
    PYTHON_RAN=true
    CSP_TMP_CHECK=$(echo "$TMP_PY" | xargs grep -l \
        "TroughPhysical\|EmpiricalTrough\|trough\|solar_mult\|tshours" \
        2>/dev/null | head -3)
    if [ -n "$CSP_TMP_CHECK" ]; then
        CSP_MODEL_USED=true
    fi
fi

# Parse output JSON for verification metrics
NUM_SM_VALUES="0"
MIN_LCOE="0"
MAX_CF="0"
FIRST_AEP="0"
OPTIMAL_SM="0"
HAS_CONFIGS=false

if [ "$FILE_EXISTS" = "true" ]; then
    # Extract number of configurations
    NUM_SM_VALUES=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    configs = None
    for key in ['configurations', 'configs', 'results', 'simulations']:
        if key in d and isinstance(d[key], list):
            configs = d[key]
            break
    print(len(configs) if configs else 0)
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")

    # Extract min LCOE across all configs
    MIN_LCOE=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    configs = None
    for key in ['configurations', 'configs', 'results', 'simulations']:
        if key in d and isinstance(d[key], list):
            configs = d[key]
            break
    if not configs:
        print(0)
        sys.exit(0)
    lcoes = []
    for cfg in configs:
        if isinstance(cfg, dict):
            for k in ['lcoe_real_usd_per_mwh', 'lcoe_real', 'lcoe', 'LCOE', 'lcoe_usd_per_mwh']:
                v = cfg.get(k)
                if v and isinstance(v, (int, float)) and v > 0:
                    lcoes.append(float(v))
                    break
    print(min(lcoes) if lcoes else 0)
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")

    # Extract max capacity factor
    MAX_CF=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    configs = None
    for key in ['configurations', 'configs', 'results', 'simulations']:
        if key in d and isinstance(d[key], list):
            configs = d[key]
            break
    if not configs:
        print(0)
        sys.exit(0)
    cfs = []
    for cfg in configs:
        if isinstance(cfg, dict):
            for k in ['capacity_factor_pct', 'capacity_factor', 'cf_pct', 'cf', 'CF']:
                v = cfg.get(k)
                if v and isinstance(v, (int, float)) and v > 0:
                    cfs.append(float(v))
                    break
    print(max(cfs) if cfs else 0)
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")

    # Extract first AEP value (in MWh)
    FIRST_AEP=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    configs = None
    for key in ['configurations', 'configs', 'results', 'simulations']:
        if key in d and isinstance(d[key], list):
            configs = d[key]
            break
    if not configs or len(configs) == 0:
        print(0)
        sys.exit(0)
    cfg = configs[0]
    if isinstance(cfg, dict):
        for k in ['annual_energy_mwh', 'annual_energy', 'aep_mwh', 'energy_mwh']:
            v = cfg.get(k)
            if v and isinstance(v, (int, float)) and v > 0:
                # If value appears to be in kWh, convert to MWh
                val = float(v)
                if val > 1000000:
                    val = val / 1000
                print(val)
                sys.exit(0)
    print(0)
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")

    # Extract optimal solar multiple
    OPTIMAL_SM=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    for k in ['optimal_solar_multiple', 'optimal_sm', 'best_solar_multiple', 'optimal']:
        v = d.get(k)
        if v is not None and isinstance(v, (int, float)) and v > 0:
            print(float(v))
            sys.exit(0)
    print(0)
except Exception as e:
    print(0)
" 2>/dev/null || echo "0")

    if [ "$NUM_SM_VALUES" -ge 2 ] 2>/dev/null; then
        HAS_CONFIGS=true
    fi
fi

# Write result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "csp_model_used": $CSP_MODEL_USED,
    "python_ran": $PYTHON_RAN,
    "num_sm_values": $NUM_SM_VALUES,
    "has_configs": $HAS_CONFIGS,
    "min_lcoe": $MIN_LCOE,
    "max_cf": $MAX_CF,
    "first_aep": $FIRST_AEP,
    "optimal_sm": $OPTIMAL_SM,
    "task_start": $TASK_START
}
EOF

echo "=== Export Complete ==="
echo "Result written to /tmp/task_result.json"
cat /tmp/task_result.json
