#!/bin/bash
echo "=== Exporting genomics_variant_qc result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
take_screenshot /tmp/task_end.png

# Paths
CSV_PATH="/home/ga/RProjects/output/variant_qc_summary.csv"
PNG_PATH="/home/ga/RProjects/output/population_pca.png"
SCRIPT_PATH="/home/ga/RProjects/variant_analysis.R"

# 1. Check CSV
CSV_EXISTS="false"
CSV_IS_NEW="false"
HAS_ORIG_COL="false"
HAS_FILT_COL="false"
ORIG_VAL=0
FILT_VAL=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi

    # Read CSV contents using Python
    PY_OUT=$(python3 << 'PYEOF'
import csv, sys
try:
    with open('/home/ga/RProjects/output/variant_qc_summary.csv', 'r') as f:
        reader = csv.DictReader(f)
        headers = [h.lower().strip() for h in (reader.fieldnames or [])]
        rows = list(reader)
        
        has_orig = any('original' in h for h in headers)
        has_filt = any('filtered' in h for h in headers)
        
        orig_val = 0
        filt_val = 0
        
        if rows:
            orig_col = next((h for h in reader.fieldnames if 'original' in h.lower()), None)
            filt_col = next((h for h in reader.fieldnames if 'filtered' in h.lower()), None)
            
            if orig_col and rows[0].get(orig_col):
                try: orig_val = int(float(rows[0][orig_col]))
                except: pass
            if filt_col and rows[0].get(filt_col):
                try: filt_val = int(float(rows[0][filt_col]))
                except: pass
                
        print(f"{str(has_orig).lower()}|{str(has_filt).lower()}|{orig_val}|{filt_val}")
except Exception as e:
    print("false|false|0|0")
PYEOF
)
    IFS='|' read -r HAS_ORIG_COL HAS_FILT_COL ORIG_VAL FILT_VAL <<< "$PY_OUT"
fi

# 2. Check PNG
PNG_EXISTS="false"
PNG_IS_NEW="false"
PNG_SIZE_KB=0

if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PNG_IS_NEW="true"
    fi
    PNG_SIZE_KB=$(du -k "$PNG_PATH" 2>/dev/null | cut -f1)
fi

# 3. Check Script
SCRIPT_EXISTS="false"
SCRIPT_IS_NEW="false"
HAS_VCFR="false"
HAS_ADEGENET="false"
HAS_FILTERING="false"
HAS_GENLIGHT="false"

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_IS_NEW="true"
    fi
    
    CODE=$(grep -v '^\s*#' "$SCRIPT_PATH")
    echo "$CODE" | grep -qiE "read\.vcfR|extract\.gt" && HAS_VCFR="true"
    echo "$CODE" | grep -qiE "vcfR2genlight|adegenet|glPca" && HAS_ADEGENET="true"
    echo "$CODE" | grep -qiE "is\.na|DP|rowMeans|apply" && HAS_FILTERING="true"
    echo "$CODE" | grep -qiE "genlight" && HAS_GENLIGHT="true"
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_has_orig_col": $HAS_ORIG_COL,
    "csv_has_filt_col": $HAS_FILT_COL,
    "csv_orig_val": $ORIG_VAL,
    "csv_filt_val": $FILT_VAL,
    "png_exists": $PNG_EXISTS,
    "png_is_new": $PNG_IS_NEW,
    "png_size_kb": $PNG_SIZE_KB,
    "script_exists": $SCRIPT_EXISTS,
    "script_is_new": $SCRIPT_IS_NEW,
    "has_vcfr": $HAS_VCFR,
    "has_adegenet": $HAS_ADEGENET,
    "has_filtering": $HAS_FILTERING,
    "has_genlight": $HAS_GENLIGHT,
    "timestamp": "$(date -Iseconds)"
}
EOF

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/task_result.json
echo "=== Export complete ==="