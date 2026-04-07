#!/bin/bash
echo "=== Exporting mortality_leecarter_forecast result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

take_screenshot /tmp/task_final.png

E0_CSV="/home/ga/RProjects/output/mortality_forecast_e0.csv"
PARAMS_CSV="/home/ga/RProjects/output/leecarter_parameters.csv"
PLOT_PNG="/home/ga/RProjects/output/kt_trend_plot.png"
SCRIPT_PATH="/home/ga/RProjects/mortality_forecast.R"

# ---- R Script Check ----
SCRIPT_MODIFIED=false
SCRIPT_HAS_DEMOGRAPHY=false
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    [ "$SCRIPT_MTIME" -gt "$TASK_START" ] && SCRIPT_MODIFIED=true
    if grep -qi "demography" "$SCRIPT_PATH"; then
        SCRIPT_HAS_DEMOGRAPHY=true
    fi
fi

# ---- Parameters CSV Check ----
PARAMS_EXISTS=false
PARAMS_IS_NEW=false
PARAMS_HAS_AX=false
PARAMS_HAS_BX=false
PARAMS_ROW_COUNT=0

if [ -f "$PARAMS_CSV" ]; then
    PARAMS_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$PARAMS_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && PARAMS_IS_NEW=true
    
    PY_OUT_PARAMS=$(python3 << 'PYEOF'
import csv, sys
try:
    with open('/home/ga/RProjects/output/leecarter_parameters.csv') as f:
        reader = csv.DictReader(f)
        headers = [h.lower().strip() for h in (reader.fieldnames or [])]
        has_ax = any('ax' in h or 'a_x' in h or 'a' == h for h in headers)
        has_bx = any('bx' in h or 'b_x' in h or 'b' == h for h in headers)
        rows = list(reader)
        row_cnt = len(rows)
        print(f"{str(has_ax).lower()}|{str(has_bx).lower()}|{row_cnt}")
except Exception as e:
    print("false|false|0")
PYEOF
)
    PARAMS_HAS_AX=$(echo "$PY_OUT_PARAMS" | cut -d'|' -f1)
    PARAMS_HAS_BX=$(echo "$PY_OUT_PARAMS" | cut -d'|' -f2)
    PARAMS_ROW_COUNT=$(echo "$PY_OUT_PARAMS" | cut -d'|' -f3)
fi

# ---- Forecast CSV Check ----
E0_EXISTS=false
E0_IS_NEW=false
E0_ROW_COUNT=0
E0_STARTS_2007=false
E0_ENDS_2036=false
E0_PLAUSIBLE=false

if [ -f "$E0_CSV" ]; then
    E0_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$E0_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && E0_IS_NEW=true

    PY_OUT_E0=$(python3 << 'PYEOF'
import csv, sys
try:
    with open('/home/ga/RProjects/output/mortality_forecast_e0.csv') as f:
        reader = csv.DictReader(f)
        headers = [h.lower().strip() for h in (reader.fieldnames or [])]
        rows = list(reader)
        row_cnt = len(rows)
        starts_2007 = False
        ends_2036 = False
        e0_plausible = False
        
        # Identify columns
        yr_col = next((h for h in reader.fieldnames if 'year' in h.lower() or 'time' in h.lower() or 'x' in h.lower() or h.lower() == ''), None)
        e0_col = next((h for h in reader.fieldnames if 'e0' in h.lower() or 'life' in h.lower() or 'exp' in h.lower() or 'y' in h.lower() or 'series' in h.lower() or 'point' in h.lower() or 'mean' in h.lower()), None)
        
        if yr_col and e0_col and rows:
            yrs = []
            e0s = []
            for r in rows:
                try:
                    y_val = float(r.get(yr_col, '').strip().replace('"', ''))
                    yrs.append(int(y_val))
                except:
                    pass
                try:
                    e_val = float(r.get(e0_col, '').strip().replace('"', ''))
                    e0s.append(e_val)
                except:
                    pass
            
            if yrs:
                if 2006 <= min(yrs) <= 2008: starts_2007 = True
                if max(yrs) >= 2035: ends_2036 = True
            if e0s:
                # Plausible life expectancy for France in 2030s is ~83-86 years
                if max(e0s) > 80.0 and max(e0s) < 95.0: e0_plausible = True
        
        print(f"{row_cnt}|{str(starts_2007).lower()}|{str(ends_2036).lower()}|{str(e0_plausible).lower()}")
except Exception as e:
    print(f"0|false|false|false")
PYEOF
)
    E0_ROW_COUNT=$(echo "$PY_OUT_E0" | cut -d'|' -f1)
    E0_STARTS_2007=$(echo "$PY_OUT_E0" | cut -d'|' -f2)
    E0_ENDS_2036=$(echo "$PY_OUT_E0" | cut -d'|' -f3)
    E0_PLAUSIBLE=$(echo "$PY_OUT_E0" | cut -d'|' -f4)
fi

# ---- Plot PNG Check ----
PLOT_EXISTS=false
PLOT_IS_NEW=false
PLOT_SIZE_BYTES=0

if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS=true
    PLOT_MTIME=$(stat -c %Y "$PLOT_PNG" 2>/dev/null || echo "0")
    [ "$PLOT_MTIME" -gt "$TASK_START" ] && PLOT_IS_NEW=true
    PLOT_SIZE_BYTES=$(stat -c %s "$PLOT_PNG" 2>/dev/null || echo "0")
fi

# Build result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "script_modified": $SCRIPT_MODIFIED,
    "script_has_demography": $SCRIPT_HAS_DEMOGRAPHY,
    "params_exists": $PARAMS_EXISTS,
    "params_is_new": $PARAMS_IS_NEW,
    "params_has_ax": $PARAMS_HAS_AX,
    "params_has_bx": $PARAMS_HAS_BX,
    "params_row_count": $PARAMS_ROW_COUNT,
    "e0_exists": $E0_EXISTS,
    "e0_is_new": $E0_IS_NEW,
    "e0_row_count": $E0_ROW_COUNT,
    "e0_starts_2007": $E0_STARTS_2007,
    "e0_ends_2036": $E0_ENDS_2036,
    "e0_plausible": $E0_PLAUSIBLE,
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_IS_NEW,
    "plot_size_bytes": $PLOT_SIZE_BYTES,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/mortality_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/mortality_task_result.json
chmod 666 /tmp/mortality_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/mortality_task_result.json