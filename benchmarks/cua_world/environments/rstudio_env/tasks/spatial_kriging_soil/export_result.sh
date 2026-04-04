#!/bin/bash
echo "=== Exporting Spatial Kriging Soil Result ==="

TASK_START=$(cat /tmp/spatial_kriging_soil_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/spatial_kriging_soil_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/spatial_kriging_soil_end_screenshot.png 2>/dev/null || true

VARIO_CSV="/home/ga/RProjects/output/zinc_variogram.csv"
VARIO_PTS_CSV="/home/ga/RProjects/output/zinc_variogram_points.csv"
PRED_CSV="/home/ga/RProjects/output/zinc_kriging_predictions.csv"
MORAN_CSV="/home/ga/RProjects/output/zinc_moran_test.csv"
MAP_PNG="/home/ga/RProjects/output/zinc_kriging_map.png"

# --- Variogram parameters CSV ---
VARIO_EXISTS=false
VARIO_IS_NEW=false
VARIO_HAS_COLS=false
VARIO_PARAMS_VALID=false

if [ -f "$VARIO_CSV" ]; then
    VARIO_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$VARIO_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && VARIO_IS_NEW=true

    VARIO_PY=$(python3 << PYEOF 2>/dev/null
import csv, sys

path = "$VARIO_CSV"
try:
    with open(path, newline='') as f:
        reader = csv.DictReader(f)
        headers = [h.lower().strip() for h in (reader.fieldnames or [])]
        rows = list(reader)

    has_model = any('model' in h or 'type' in h for h in headers)
    has_nugget = any('nugget' in h for h in headers)
    has_sill = any('sill' in h or 'psill' in h for h in headers)
    has_range = any('range' in h for h in headers)
    has_cols = has_nugget and has_sill and has_range

    # Validate parameter ranges (log-scale zinc)
    params_valid = False
    if has_cols and rows:
        try:
            nugget_col = next((h for h in headers if 'nugget' in h), None)
            sill_col   = next((h for h in headers if 'sill' in h or 'psill' in h), None)
            range_col  = next((h for h in headers if 'range' in h), None)

            nugget = float(rows[0].get(nugget_col, -1))
            sill   = float(rows[0].get(sill_col, -1))
            rng    = float(rows[0].get(range_col, -1))

            # Expected: nugget 0-0.5, psill 0.1-1.5, range 50-3000m
            params_valid = (0 <= nugget <= 0.5) and (0.05 <= sill <= 1.5) and (50 <= rng <= 3000)
        except:
            pass

    print(f"has_cols={str(has_cols).lower()}|params_valid={str(params_valid).lower()}")
except Exception as e:
    print("has_cols=false|params_valid=false")
PYEOF
)
    IFS='|' read -r V1 V2 <<< "$VARIO_PY"
    VARIO_HAS_COLS=$(echo "$V1" | cut -d= -f2)
    VARIO_PARAMS_VALID=$(echo "$V2" | cut -d= -f2)
fi

# --- Variogram points CSV ---
VARIO_PTS_EXISTS=false
VARIO_PTS_IS_NEW=false
VARIO_PTS_ROW_COUNT=0

if [ -f "$VARIO_PTS_CSV" ]; then
    VARIO_PTS_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$VARIO_PTS_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && VARIO_PTS_IS_NEW=true
    VARIO_PTS_ROW_COUNT=$(wc -l < "$VARIO_PTS_CSV" 2>/dev/null || echo "0")
fi

# --- Kriging predictions CSV ---
PRED_EXISTS=false
PRED_IS_NEW=false
PRED_HAS_COLS=false
PRED_VALUES_VALID=false
PRED_ROW_COUNT=0

if [ -f "$PRED_CSV" ]; then
    PRED_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$PRED_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && PRED_IS_NEW=true
    PRED_ROW_COUNT=$(wc -l < "$PRED_CSV" 2>/dev/null || echo "0")

    PRED_PY=$(python3 << PYEOF 2>/dev/null
import csv, sys, math

path = "$PRED_CSV"
try:
    with open(path, newline='') as f:
        reader = csv.DictReader(f)
        headers = [h.lower().strip() for h in (reader.fieldnames or [])]
        rows = list(reader)

    has_x = any('x' == h or 'lon' in h or 'easting' in h for h in headers)
    has_y = any('y' == h or 'lat' in h or 'northing' in h for h in headers)
    has_pred = any('pred' in h or 'zinc' in h or 'mean' in h for h in headers)
    has_var  = any('var' in h or 'se' in h or 'sigma' in h for h in headers)
    has_cols = has_x and has_y and has_pred

    # Check that predictions are in reasonable range (50-3000 ppm back-transformed)
    pred_col = next((h for h in headers if 'pred' in h or 'zinc' in h), None)
    values_valid = False
    if pred_col and rows:
        try:
            vals = [float(r[pred_col]) for r in rows[:100]
                    if r.get(pred_col, '') not in ('', 'NA', 'nan', 'NaN')]
            if vals:
                # Either log-scale (3-8) or original scale (50-3000)
                log_scale = all(1 <= v <= 12 for v in vals)
                orig_scale = all(20 <= v <= 10000 for v in vals)
                values_valid = log_scale or orig_scale
        except:
            pass

    print(f"has_cols={str(has_cols).lower()}|values_valid={str(values_valid).lower()}|nrows={len(rows)}")
except Exception as e:
    print("has_cols=false|values_valid=false|nrows=0")
PYEOF
)
    IFS='|' read -r P1 P2 P3 <<< "$PRED_PY"
    PRED_HAS_COLS=$(echo "$P1" | cut -d= -f2)
    PRED_VALUES_VALID=$(echo "$P2" | cut -d= -f2)
fi

# --- Moran test CSV ---
MORAN_EXISTS=false
MORAN_IS_NEW=false
MORAN_HAS_COLS=false

if [ -f "$MORAN_CSV" ]; then
    MORAN_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$MORAN_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && MORAN_IS_NEW=true

    MORAN_CHECK=$(python3 -c "
import csv, os
path = '$MORAN_CSV'
if not os.path.exists(path):
    print('false')
    exit()
with open(path, newline='') as f:
    reader = csv.DictReader(f)
    headers = [h.lower().strip() for h in (reader.fieldnames or [])]
has_stat = any('stat' in h or 'moran' in h or 'i' == h for h in headers)
has_pv   = any('p_value' in h or 'pval' in h or 'p' == h for h in headers)
print(str(has_stat and has_pv).lower())
" 2>/dev/null || echo "false")
    MORAN_HAS_COLS="$MORAN_CHECK"
fi

# --- Map PNG ---
MAP_EXISTS=false
MAP_IS_NEW=false
MAP_SIZE=0
MAP_IS_PNG=false

if [ -f "$MAP_PNG" ]; then
    MAP_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$MAP_PNG" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && MAP_IS_NEW=true
    MAP_SIZE=$(stat -c %s "$MAP_PNG" 2>/dev/null || echo "0")
    PNG_HEADER=$(python3 -c "
with open('$MAP_PNG', 'rb') as f:
    h = f.read(8)
print(str(h == b'\x89PNG\r\n\x1a\n').lower())
" 2>/dev/null || echo "false")
    MAP_IS_PNG="$PNG_HEADER"
fi

# --- Script checks ---
SCRIPT="/home/ga/RProjects/spatial_analysis.R"
SCRIPT_IS_MODIFIED=false
SCRIPT_HAS_VARIOGRAM=false
SCRIPT_HAS_KRIGE=false
SCRIPT_HAS_MORAN=false

if [ -f "$SCRIPT" ]; then
    FILE_MTIME=$(stat -c %Y "$SCRIPT" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && SCRIPT_IS_MODIFIED=true
    grep -q "variogram(" "$SCRIPT" 2>/dev/null && SCRIPT_HAS_VARIOGRAM=true
    grep -q "krige(" "$SCRIPT" 2>/dev/null && SCRIPT_HAS_KRIGE=true
    grep -qiE "moran|Moran\.I|moran\.test" "$SCRIPT" 2>/dev/null && SCRIPT_HAS_MORAN=true
fi

cat > /tmp/spatial_kriging_soil_result.json << EOF
{
    "task_start": $TASK_START,
    "variogram_csv": {
        "exists": $VARIO_EXISTS,
        "is_new": $VARIO_IS_NEW,
        "has_required_columns": $VARIO_HAS_COLS,
        "parameters_valid": $VARIO_PARAMS_VALID
    },
    "variogram_points_csv": {
        "exists": $VARIO_PTS_EXISTS,
        "is_new": $VARIO_PTS_IS_NEW,
        "row_count": $VARIO_PTS_ROW_COUNT
    },
    "predictions_csv": {
        "exists": $PRED_EXISTS,
        "is_new": $PRED_IS_NEW,
        "has_required_columns": $PRED_HAS_COLS,
        "values_in_valid_range": $PRED_VALUES_VALID,
        "row_count": $PRED_ROW_COUNT
    },
    "moran_csv": {
        "exists": $MORAN_EXISTS,
        "is_new": $MORAN_IS_NEW,
        "has_required_columns": $MORAN_HAS_COLS
    },
    "map_png": {
        "exists": $MAP_EXISTS,
        "is_new": $MAP_IS_NEW,
        "size_bytes": $MAP_SIZE,
        "is_valid_png": $MAP_IS_PNG
    },
    "script": {
        "modified": $SCRIPT_IS_MODIFIED,
        "has_variogram": $SCRIPT_HAS_VARIOGRAM,
        "has_krige": $SCRIPT_HAS_KRIGE,
        "has_moran": $SCRIPT_HAS_MORAN
    }
}
EOF

echo "=== Export Complete ==="
cat /tmp/spatial_kriging_soil_result.json
