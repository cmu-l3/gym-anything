#!/bin/bash
echo "=== Exporting spatial_autocorrelation_sids result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

take_screenshot /tmp/task_end.png

# Initialize result variables
GLOBAL_TXT_EXISTS=false
GLOBAL_TXT_NEW=false
GLOBAL_I_VALUE=""

LISA_CSV_EXISTS=false
LISA_CSV_NEW=false
LISA_HAS_RATE=false
LISA_HAS_PVAL=false

SCATTER_PNG_EXISTS=false
SCATTER_PNG_NEW=false
SCATTER_SIZE_KB=0

MAP_PNG_EXISTS=false
MAP_PNG_NEW=false
MAP_SIZE_KB=0

SCRIPT_MODIFIED=false
HAS_SPDEP_CALLS=false

# 1. Check Global Moran Text
TXT_FILE="$OUTPUT_DIR/global_moran.txt"
if [ -f "$TXT_FILE" ]; then
    GLOBAL_TXT_EXISTS=true
    if [ $(stat -c %Y "$TXT_FILE") -gt "$TASK_START" ]; then
        GLOBAL_TXT_NEW=true
    fi
    # Try to extract Moran's I statistic using grep/awk
    # Look for patterns like "Moran I statistic: 0.42" or "statistic = 0.42"
    GLOBAL_I_VALUE=$(grep -oE "0\.[0-9]+" "$TXT_FILE" | head -1)
fi

# 2. Check LISA CSV
CSV_FILE="$OUTPUT_DIR/nc_lisa_results.csv"
if [ -f "$CSV_FILE" ]; then
    LISA_CSV_EXISTS=true
    if [ $(stat -c %Y "$CSV_FILE") -gt "$TASK_START" ]; then
        LISA_CSV_NEW=true
    fi
    
    # Check headers
    HEADERS=$(head -1 "$CSV_FILE" | tr '[:upper:]' '[:lower:]')
    if echo "$HEADERS" | grep -q "rate"; then LISA_HAS_RATE=true; fi
    if echo "$HEADERS" | grep -qE "p_val|prob|pr\("; then LISA_HAS_PVAL=true; fi
fi

# 3. Check Images
SCATTER_FILE="$OUTPUT_DIR/moran_scatterplot.png"
if [ -f "$SCATTER_FILE" ]; then
    SCATTER_PNG_EXISTS=true
    if [ $(stat -c %Y "$SCATTER_FILE") -gt "$TASK_START" ]; then
        SCATTER_PNG_NEW=true
    fi
    SCATTER_SIZE_KB=$(du -k "$SCATTER_FILE" | cut -f1)
fi

MAP_FILE="$OUTPUT_DIR/lisa_cluster_map.png"
if [ -f "$MAP_FILE" ]; then
    MAP_PNG_EXISTS=true
    if [ $(stat -c %Y "$MAP_FILE") -gt "$TASK_START" ]; then
        MAP_PNG_NEW=true
    fi
    MAP_SIZE_KB=$(du -k "$MAP_FILE" | cut -f1)
fi

# 4. Check Script
SCRIPT_FILE="/home/ga/RProjects/sids_analysis.R"
if [ -f "$SCRIPT_FILE" ]; then
    if [ $(stat -c %Y "$SCRIPT_FILE") -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED=true
    fi
    # Check for key functions
    CONTENT=$(cat "$SCRIPT_FILE")
    if echo "$CONTENT" | grep -q "poly2nb" && echo "$CONTENT" | grep -q "moran.test"; then
        HAS_SPDEP_CALLS=true
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "global_txt_exists": $GLOBAL_TXT_EXISTS,
    "global_txt_new": $GLOBAL_TXT_NEW,
    "global_i_extracted": "$GLOBAL_I_VALUE",
    "lisa_csv_exists": $LISA_CSV_EXISTS,
    "lisa_csv_new": $LISA_CSV_NEW,
    "lisa_has_rate_col": $LISA_HAS_RATE,
    "lisa_has_pval_col": $LISA_HAS_PVAL,
    "scatter_png_exists": $SCATTER_PNG_EXISTS,
    "scatter_png_new": $SCATTER_PNG_NEW,
    "scatter_size_kb": $SCATTER_SIZE_KB,
    "map_png_exists": $MAP_PNG_EXISTS,
    "map_png_new": $MAP_PNG_NEW,
    "map_size_kb": $MAP_SIZE_KB,
    "script_modified": $SCRIPT_MODIFIED,
    "has_spdep_calls": $HAS_SPDEP_CALLS
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="