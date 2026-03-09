#!/bin/bash
echo "=== Exporting NOAA Climate Forecast Result ==="

TASK_START=$(cat /tmp/noaa_climate_forecast_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/noaa_climate_forecast_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/noaa_climate_forecast_end_screenshot.png 2>/dev/null || true

STL_CSV="/home/ga/RProjects/output/climate_stl_components.csv"
FORECAST_CSV="/home/ga/RProjects/output/climate_forecast.csv"
BP_CSV="/home/ga/RProjects/output/climate_breakpoints.csv"
PLOT_PNG="/home/ga/RProjects/output/climate_analysis.png"

# --- STL components CSV ---
STL_EXISTS=false
STL_IS_NEW=false
STL_HAS_TREND=false
STL_ROW_COUNT=0
STL_TREND_POSITIVE=false

if [ -f "$STL_CSV" ]; then
    STL_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$STL_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && STL_IS_NEW=true
    STL_ROW_COUNT=$(wc -l < "$STL_CSV" 2>/dev/null || echo "0")

    STL_PY=$(python3 << PYEOF 2>/dev/null
import csv, sys

path = "$STL_CSV"
try:
    with open(path, newline='') as f:
        reader = csv.DictReader(f)
        headers = [h.lower().strip() for h in (reader.fieldnames or [])]
        rows = list(reader)

    has_trend = any('trend' in h for h in headers)
    has_year = any('year' in h for h in headers)

    # Check if trend is increasing (recent decades warmer than early)
    trend_col = next((h for h in headers if 'trend' in h), None)
    year_col = next((h for h in headers if 'year' in h), None)

    trend_positive = False
    if trend_col and year_col and len(rows) >= 100:
        try:
            early_vals = [float(r[trend_col]) for r in rows[:30]
                          if r.get(trend_col, '') not in ('', 'NA', 'nan', 'NaN')]
            late_vals  = [float(r[trend_col]) for r in rows[-30:]
                          if r.get(trend_col, '') not in ('', 'NA', 'nan', 'NaN')]
            if early_vals and late_vals:
                trend_positive = (sum(late_vals)/len(late_vals)) > (sum(early_vals)/len(early_vals))
        except:
            pass

    print(f"has_trend={str(has_trend).lower()}|has_year={str(has_year).lower()}|trend_positive={str(trend_positive).lower()}|nrows={len(rows)}")
except Exception as e:
    print("has_trend=false|has_year=false|trend_positive=false|nrows=0")
PYEOF
)
    IFS='|' read -r T1 T2 T3 T4 <<< "$STL_PY"
    STL_HAS_TREND=$(echo "$T1" | cut -d= -f2)
    STL_TREND_POSITIVE=$(echo "$T3" | cut -d= -f2)
fi

# --- Forecast CSV ---
FCST_EXISTS=false
FCST_IS_NEW=false
FCST_HAS_COLS=false
FCST_ROW_COUNT=0
FCST_DIRECTION_VALID=false

if [ -f "$FORECAST_CSV" ]; then
    FCST_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$FORECAST_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && FCST_IS_NEW=true
    FCST_ROW_COUNT=$(wc -l < "$FORECAST_CSV" 2>/dev/null || echo "0")

    FCST_PY=$(python3 << PYEOF 2>/dev/null
import csv, sys

path = "$FORECAST_CSV"
try:
    with open(path, newline='') as f:
        reader = csv.DictReader(f)
        headers = [h.lower().strip() for h in (reader.fieldnames or [])]
        rows = list(reader)

    has_forecast = any('forecast' in h or 'mean' in h or 'point' in h for h in headers)
    has_ci = any('lower' in h or 'upper' in h or '80' in h or '95' in h for h in headers)
    has_year = any('year' in h for h in headers)

    # Check forecast values are in a reasonable range (0.5-3.0 for 2024-2033)
    fcst_col = next((h for h in headers if 'forecast' in h or 'mean' in h or h == 'point'), None)
    direction_valid = False
    if fcst_col and rows:
        try:
            vals = [float(r[fcst_col]) for r in rows
                    if r.get(fcst_col, '') not in ('', 'NA', 'nan', 'NaN')]
            if vals:
                # Forecasts should be positive anomaly and between -1 and 3
                direction_valid = all(-1.0 <= v <= 3.0 for v in vals) and len(vals) >= 5
        except:
            pass

    print(f"has_cols={str(has_forecast and has_ci).lower()}|direction_valid={str(direction_valid).lower()}|nrows={len(rows)}")
except Exception as e:
    print("has_cols=false|direction_valid=false|nrows=0")
PYEOF
)
    IFS='|' read -r F1 F2 F3 <<< "$FCST_PY"
    FCST_HAS_COLS=$(echo "$F1" | cut -d= -f2)
    FCST_DIRECTION_VALID=$(echo "$F2" | cut -d= -f2)
fi

# --- Breakpoints CSV ---
BP_EXISTS=false
BP_IS_NEW=false
BP_HAS_COLS=false
BP_ROW_COUNT=0

if [ -f "$BP_CSV" ]; then
    BP_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$BP_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && BP_IS_NEW=true
    BP_ROW_COUNT=$(wc -l < "$BP_CSV" 2>/dev/null || echo "0")

    BP_CHECK=$(python3 -c "
import csv, os
path = '$BP_CSV'
if not os.path.exists(path):
    print('false')
    exit()
with open(path, newline='') as f:
    reader = csv.DictReader(f)
    headers = [h.lower().strip() for h in (reader.fieldnames or [])]
has_bp = any('break' in h or 'year' in h for h in headers)
has_mean = any('mean' in h or 'segment' in h for h in headers)
print(str(has_bp and has_mean).lower())
" 2>/dev/null || echo "false")
    BP_HAS_COLS="$BP_CHECK"
fi

# --- Plot PNG ---
PLOT_EXISTS=false
PLOT_IS_NEW=false
PLOT_SIZE=0
PLOT_IS_PNG=false

if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$PLOT_PNG" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && PLOT_IS_NEW=true
    PLOT_SIZE=$(stat -c %s "$PLOT_PNG" 2>/dev/null || echo "0")
    PNG_HEADER=$(python3 -c "
with open('$PLOT_PNG', 'rb') as f:
    h = f.read(8)
print(str(h == b'\x89PNG\r\n\x1a\n').lower())
" 2>/dev/null || echo "false")
    PLOT_IS_PNG="$PNG_HEADER"
fi

# --- Script checks ---
SCRIPT="/home/ga/RProjects/climate_analysis.R"
SCRIPT_IS_MODIFIED=false
SCRIPT_HAS_STL=false
SCRIPT_HAS_AUTOARIMA=false
SCRIPT_HAS_CPT=false

if [ -f "$SCRIPT" ]; then
    FILE_MTIME=$(stat -c %Y "$SCRIPT" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && SCRIPT_IS_MODIFIED=true
    grep -q "stl(" "$SCRIPT" 2>/dev/null && SCRIPT_HAS_STL=true
    grep -qE "auto\.arima|auto_arima" "$SCRIPT" 2>/dev/null && SCRIPT_HAS_AUTOARIMA=true
    grep -qE "cpt\.|changepoint" "$SCRIPT" 2>/dev/null && SCRIPT_HAS_CPT=true
fi

cat > /tmp/noaa_climate_forecast_result.json << EOF
{
    "task_start": $TASK_START,
    "stl_csv": {
        "exists": $STL_EXISTS,
        "is_new": $STL_IS_NEW,
        "has_trend_column": $STL_HAS_TREND,
        "trend_is_positive": $STL_TREND_POSITIVE,
        "row_count": $STL_ROW_COUNT
    },
    "forecast_csv": {
        "exists": $FCST_EXISTS,
        "is_new": $FCST_IS_NEW,
        "has_required_columns": $FCST_HAS_COLS,
        "forecast_values_valid": $FCST_DIRECTION_VALID,
        "row_count": $FCST_ROW_COUNT
    },
    "breakpoints_csv": {
        "exists": $BP_EXISTS,
        "is_new": $BP_IS_NEW,
        "has_required_columns": $BP_HAS_COLS,
        "row_count": $BP_ROW_COUNT
    },
    "plot_png": {
        "exists": $PLOT_EXISTS,
        "is_new": $PLOT_IS_NEW,
        "size_bytes": $PLOT_SIZE,
        "is_valid_png": $PLOT_IS_PNG
    },
    "script": {
        "modified": $SCRIPT_IS_MODIFIED,
        "has_stl": $SCRIPT_HAS_STL,
        "has_auto_arima": $SCRIPT_HAS_AUTOARIMA,
        "has_changepoint": $SCRIPT_HAS_CPT
    }
}
EOF

echo "=== Export Complete ==="
cat /tmp/noaa_climate_forecast_result.json
