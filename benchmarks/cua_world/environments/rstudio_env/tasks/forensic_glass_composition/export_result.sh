#!/bin/bash
echo "=== Exporting Forensic Glass Composition Result ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Helper function to check file stats ---
check_file() {
    local file="$1"
    local exists=false
    local is_new=false
    local size=0

    if [ -f "$file" ]; then
        exists=true
        size=$(stat -c %s "$file")
        mtime=$(stat -c %Y "$file")
        if [ "$mtime" -gt "$TASK_START" ]; then
            is_new=true
        fi
    fi
    echo "\"exists\": $exists, \"is_new\": $is_new, \"size\": $size"
}

# --- 1. Check Geometric Means CSV ---
GEO_CSV="$OUTPUT_DIR/glass_geometric_means.csv"
GEO_STATS=$(check_file "$GEO_CSV")
# Verify it has rows for glass types (expecting header + ~6 rows)
GEO_ROWS=0
if [ -f "$GEO_CSV" ]; then
    GEO_ROWS=$(wc -l < "$GEO_CSV")
fi

# --- 2. Check CLR Transformed CSV ---
CLR_CSV="$OUTPUT_DIR/glass_clr_transformed.csv"
CLR_STATS=$(check_file "$CLR_CSV")
# Verify CLR properties: row sums should be close to 0
CLR_VALID="false"
if [ -f "$CLR_CSV" ]; then
    # Use python to verify mathematical property of CLR (sum of row approx 0)
    # and presence of negative values (log ratios)
    CLR_VALID=$(python3 -c "
import pandas as pd
import numpy as np
try:
    df = pd.read_csv('$CLR_CSV')
    # Filter numeric columns only
    df_num = df.select_dtypes(include=[np.number])
    if df_num.empty:
        print('false')
    else:
        # Check row sums (should be near 0 for CLR)
        row_sums = df_num.sum(axis=1).abs().mean()
        has_negatives = (df_num < 0).any().any()
        # Tolerance for float errors
        if row_sums < 1.0 and has_negatives:
            print('true')
        else:
            print('false')
except:
    print('false')
" 2>/dev/null || echo "false")
fi

# --- 3. Check Biplot PNG ---
BIPLOT_PNG="$OUTPUT_DIR/glass_biplot.png"
BIPLOT_STATS=$(check_file "$BIPLOT_PNG")

# --- 4. Check Ternary PNG ---
TERNARY_PNG="$OUTPUT_DIR/glass_ternary_si_na_ca.png"
TERNARY_STATS=$(check_file "$TERNARY_PNG")

# --- 5. Check Installed Packages ---
# Check R library for CoDa packages
HAS_CODA_PKG="false"
if [ -d "/home/ga/R/library/compositions" ] || \
   [ -d "/home/ga/R/library/robCompositions" ] || \
   [ -d "/home/ga/R/library/Ternary" ] || \
   [ -d "/home/ga/R/library/ggtern" ]; then
    HAS_CODA_PKG="true"
fi

# --- 6. R Script Check ---
SCRIPT_PATH="/home/ga/RProjects/glass_analysis.R"
SCRIPT_MODIFIED="false"
if [ -f "$SCRIPT_PATH" ]; then
    MTIME=$(stat -c %Y "$SCRIPT_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

# --- Construct JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "geometric_means": {
        $GEO_STATS,
        "row_count": $GEO_ROWS
    },
    "clr_transformed": {
        $CLR_STATS,
        "is_valid_clr": $CLR_VALID
    },
    "biplot": {
        $BIPLOT_STATS
    },
    "ternary": {
        $TERNARY_STATS
    },
    "has_coda_package": $HAS_CODA_PKG,
    "script_modified": $SCRIPT_MODIFIED
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="