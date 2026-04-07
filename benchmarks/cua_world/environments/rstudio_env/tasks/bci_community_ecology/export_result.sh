#!/bin/bash
echo "=== Exporting BCI Community Ecology Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUT_DIR="/home/ga/RProjects/output"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Alpha Diversity CSV
ALPHA_CSV="$OUT_DIR/bci_alpha_diversity.csv"
ALPHA_EXISTS="false"
ALPHA_NEW="false"
ALPHA_ROWS=0
ALPHA_COLS=""

if [ -f "$ALPHA_CSV" ]; then
    ALPHA_EXISTS="true"
    [ "$(stat -c %Y "$ALPHA_CSV")" -gt "$TASK_START" ] && ALPHA_NEW="true"
    ALPHA_ROWS=$(grep -cve '^\s*$' "$ALPHA_CSV") # Count non-empty lines
    ALPHA_COLS=$(head -n 1 "$ALPHA_CSV" | tr -d '\r')
fi

# 2. Check Ordination CSV
NMDS_CSV="$OUT_DIR/bci_ordination.csv"
NMDS_EXISTS="false"
NMDS_NEW="false"
NMDS_COLS=""

if [ -f "$NMDS_CSV" ]; then
    NMDS_EXISTS="true"
    [ "$(stat -c %Y "$NMDS_CSV")" -gt "$TASK_START" ] && NMDS_NEW="true"
    NMDS_COLS=$(head -n 1 "$NMDS_CSV" | tr -d '\r')
fi

# 3. Check Tests CSV
TESTS_CSV="$OUT_DIR/bci_community_tests.csv"
TESTS_EXISTS="false"
TESTS_NEW="false"
TESTS_CONTENT=""

if [ -f "$TESTS_CSV" ]; then
    TESTS_EXISTS="true"
    [ "$(stat -c %Y "$TESTS_CSV")" -gt "$TASK_START" ] && TESTS_NEW="true"
    TESTS_CONTENT=$(cat "$TESTS_CSV" | base64 -w 0)
fi

# 4. Check Figure PNG
PLOT_PNG="$OUT_DIR/bci_community_analysis.png"
PLOT_EXISTS="false"
PLOT_NEW="false"
PLOT_SIZE=0

if [ -f "$PLOT_PNG" ]; then
    PLOT_EXISTS="true"
    [ "$(stat -c %Y "$PLOT_PNG")" -gt "$TASK_START" ] && PLOT_NEW="true"
    PLOT_SIZE=$(stat -c %s "$PLOT_PNG")
fi

# 5. Check Script
SCRIPT="$OUT_DIR/../bci_analysis.R"
SCRIPT_MODIFIED="false"
HAS_VEGAN="false"

if [ -f "$SCRIPT" ]; then
    [ "$(stat -c %Y "$SCRIPT")" -gt "$TASK_START" ] && SCRIPT_MODIFIED="true"
    if grep -qi "vegan" "$SCRIPT"; then
        HAS_VEGAN="true"
    fi
fi

# Prepare files for verification (copy to /tmp/export for easy python access)
mkdir -p /tmp/export
[ -f "$ALPHA_CSV" ] && cp "$ALPHA_CSV" /tmp/export/alpha.csv
[ -f "$NMDS_CSV" ] && cp "$NMDS_CSV" /tmp/export/nmds.csv
[ -f "$TESTS_CSV" ] && cp "$TESTS_CSV" /tmp/export/tests.csv

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "alpha": {
        "exists": $ALPHA_EXISTS,
        "is_new": $ALPHA_NEW,
        "rows": $ALPHA_ROWS,
        "cols": "$ALPHA_COLS"
    },
    "nmds": {
        "exists": $NMDS_EXISTS,
        "is_new": $NMDS_NEW,
        "cols": "$NMDS_COLS"
    },
    "tests": {
        "exists": $TESTS_EXISTS,
        "is_new": $TESTS_NEW,
        "content_b64": "$TESTS_CONTENT"
    },
    "plot": {
        "exists": $PLOT_EXISTS,
        "is_new": $PLOT_NEW,
        "size_bytes": $PLOT_SIZE
    },
    "script": {
        "modified": $SCRIPT_MODIFIED,
        "has_vegan": $HAS_VEGAN
    },
    "timestamp": $(date +%s)
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"