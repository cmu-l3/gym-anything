#!/bin/bash
# Export result for pv_performance_degradation_diagnosis task
echo "=== Exporting PV Performance Degradation Diagnosis Result ==="

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/SAM_Projects/LasVegas_Performance_Diagnosis.json"
OBSERVED_YEAR4=35290

# Take end screenshot
DISPLAY=:1 import -window root /tmp/pv_diagnosis_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/pv_diagnosis_end_screenshot.png 2>/dev/null || true

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

# Anti-bypass: detect Python using PySAM for parametric sweep
PYSAM_USED=false
PYTHON_RAN=false
SWEEP_DETECTED=false

NEW_PY_FILES=$(find /home/ga -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null | head -20)
if [ -n "$NEW_PY_FILES" ]; then
    PYTHON_RAN=true
    PYSAM_CHECK=$(echo "$NEW_PY_FILES" | xargs grep -l \
        "Pvwattsv8\|Pvsamv1\|pvwatts\|PySAM\|annual_energy\|system_capacity\|soiling\|degradation" \
        2>/dev/null | head -5)
    if [ -n "$PYSAM_CHECK" ]; then
        PYSAM_USED=true
    fi
    # Check for sweep pattern (loops over soiling and degradation)
    SWEEP_CHECK=$(echo "$NEW_PY_FILES" | xargs grep -l \
        "soiling_values\|degradation_values\|for soiling\|for degr\|sweep\|parametric\|35290\|client_system_report" \
        2>/dev/null | head -5)
    if [ -n "$SWEEP_CHECK" ]; then
        SWEEP_DETECTED=true
    fi
fi

TMP_PY=$(find /tmp /root -name "*.py" -newer /home/ga/.task_start_time 2>/dev/null | head -10)
if [ -n "$TMP_PY" ]; then
    PYTHON_RAN=true
    PYSAM_TMP=$(echo "$TMP_PY" | xargs grep -l \
        "Pvwattsv8\|Pvsamv1\|annual_energy\|soiling\|degradation" \
        2>/dev/null | head -3)
    if [ -n "$PYSAM_TMP" ]; then
        PYSAM_USED=true
    fi
    SWEEP_TMP=$(echo "$TMP_PY" | xargs grep -l \
        "35290\|soiling_values\|sweep\|client_system_report" \
        2>/dev/null | head -3)
    if [ -n "$SWEEP_TMP" ]; then
        SWEEP_DETECTED=true
    fi
fi

# Parse output JSON
NUM_SWEEP_RESULTS="0"
BEST_FIT_ERROR_PCT="100"
BEST_FIT_SOILING="0"
BEST_FIT_DEGRADATION="0"
BEST_FIT_MODELED_KWH="0"
HAS_OBSERVED_DATA=false
HAS_RECOMMENDATIONS=false

if [ "$FILE_EXISTS" = "true" ]; then
    NUM_SWEEP_RESULTS=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    results = None
    for key in ['sweep_results', 'results', 'parametric_results', 'combinations']:
        if key in d and isinstance(d[key], list):
            results = d[key]
            break
    print(len(results) if results else 0)
except:
    print(0)
" 2>/dev/null || echo "0")

    BEST_FIT_DATA=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    # Try explicit best_fit field
    bf = d.get('best_fit') or d.get('best_combination') or d.get('optimal_fit')
    if bf and isinstance(bf, dict):
        soiling = float(bf.get('soiling_pct') or bf.get('soiling') or 0)
        degradation = float(bf.get('degradation_rate_pct_per_yr') or bf.get('degradation_rate') or bf.get('degradation') or 0)
        modeled = float(bf.get('modeled_year4_kwh') or bf.get('modeled_kwh') or bf.get('year4_kwh') or 0)
        error_pct = float(bf.get('error_pct') or 0)
        if error_pct == 0 and modeled > 0:
            error_pct = abs(modeled - $OBSERVED_YEAR4) / $OBSERVED_YEAR4 * 100
        print(f'{soiling},{degradation},{modeled},{error_pct:.2f}')
        sys.exit(0)
    # Fallback: find best from sweep results
    results = None
    for key in ['sweep_results', 'results', 'parametric_results', 'combinations']:
        if key in d and isinstance(d[key], list):
            results = d[key]
            break
    if not results:
        print('0,0,0,100')
        sys.exit(0)
    best = None
    best_err = 1e9
    for r in results:
        if not isinstance(r, dict):
            continue
        modeled = float(r.get('modeled_year4_kwh') or r.get('modeled_kwh') or 0)
        err = abs(modeled - $OBSERVED_YEAR4) if modeled > 0 else 1e9
        if err < best_err:
            best_err = err
            best = r
    if best:
        s = float(best.get('soiling_pct') or best.get('soiling') or 0)
        deg = float(best.get('degradation_rate_pct_per_yr') or best.get('degradation') or 0)
        mod = float(best.get('modeled_year4_kwh') or best.get('modeled_kwh') or 0)
        ep = best_err / $OBSERVED_YEAR4 * 100
        print(f'{s},{deg},{mod},{ep:.2f}')
    else:
        print('0,0,0,100')
except Exception as e:
    print(f'0,0,0,100')
" 2>/dev/null || echo "0,0,0,100")

    BEST_FIT_SOILING=$(echo "$BEST_FIT_DATA" | cut -d',' -f1)
    BEST_FIT_DEGRADATION=$(echo "$BEST_FIT_DATA" | cut -d',' -f2)
    BEST_FIT_MODELED_KWH=$(echo "$BEST_FIT_DATA" | cut -d',' -f3)
    BEST_FIT_ERROR_PCT=$(echo "$BEST_FIT_DATA" | cut -d',' -f4)

    # Check for observed production data
    HAS_OBSERVED_DATA=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    obs = d.get('observed_production') or d.get('observed_data') or d.get('actual_production')
    if obs and isinstance(obs, dict):
        # Check for year4 value close to 35290
        for k, v in obs.items():
            if isinstance(v, (int, float)) and abs(float(v) - 35290) < 500:
                print('true'); sys.exit(0)
    print('false')
except:
    print('false')
" 2>/dev/null || echo "false")

    # Check for recommendations
    HAS_RECOMMENDATIONS=$(python3 -c "
import json, sys
try:
    with open('$OUTPUT_FILE') as f:
        d = json.load(f)
    rec = d.get('recommended_actions') or d.get('recommendations') or d.get('action_items')
    if rec and isinstance(rec, list) and len(rec) >= 1:
        print('true')
    elif d.get('root_cause_analysis') and len(str(d.get('root_cause_analysis', ''))) > 20:
        print('true')
    else:
        print('false')
except:
    print('false')
" 2>/dev/null || echo "false")
fi

cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "pysam_used": $PYSAM_USED,
    "python_ran": $PYTHON_RAN,
    "sweep_detected": $SWEEP_DETECTED,
    "num_sweep_results": $NUM_SWEEP_RESULTS,
    "best_fit_soiling": $BEST_FIT_SOILING,
    "best_fit_degradation": $BEST_FIT_DEGRADATION,
    "best_fit_modeled_kwh": $BEST_FIT_MODELED_KWH,
    "best_fit_error_pct": $BEST_FIT_ERROR_PCT,
    "has_observed_data": $HAS_OBSERVED_DATA,
    "has_recommendations": $HAS_RECOMMENDATIONS,
    "task_start": $TASK_START
}
EOF

echo "=== Export Complete ==="
echo "Result written to /tmp/task_result.json"
cat /tmp/task_result.json
