#!/bin/bash
echo "=== Exporting panel_gasoline_elasticity results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

# Initialize result variables
CSV_EXISTS="false"
TXT_EXISTS="false"
PNG_EXISTS="false"
SCRIPT_MODIFIED="false"
FE_PRICE_ELASTICITY="null"
HAUSMAN_PVAL="null"
PNG_SIZE_BYTES=0

# 1. Check Model Comparison CSV
CSV_FILE="$OUTPUT_DIR/model_comparison.csv"
if [ -f "$CSV_FILE" ]; then
    CSV_MTIME=$(stat -c %Y "$CSV_FILE" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_EXISTS="true"
        
        # Extract Fixed Effects Price Elasticity using Python
        # We look for the row where model is 'fixed' (case insensitive) and get price_elasticity
        FE_PRICE_ELASTICITY=$(python3 -c "
import csv, sys
try:
    with open('$CSV_FILE', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Normalize keys to lowercase
            r = {k.lower(): v for k, v in row.items()}
            model = r.get('model', '').lower()
            if 'fixed' in model or 'within' in model:
                # Try to find price elasticity col
                for k in r:
                    if 'price' in k or 'lrpmg' in k:
                        print(r[k])
                        sys.exit(0)
    print('null')
except Exception:
    print('null')
")
    fi
fi

# 2. Check Hausman Result Text
TXT_FILE="$OUTPUT_DIR/hausman_result.txt"
if [ -f "$TXT_FILE" ]; then
    TXT_MTIME=$(stat -c %Y "$TXT_FILE" 2>/dev/null || echo "0")
    if [ "$TXT_MTIME" -gt "$TASK_START" ]; then
        TXT_EXISTS="true"
        # Try to extract a p-value number from the text
        HAUSMAN_PVAL=$(grep -oE "0\.[0-9]+" "$TXT_FILE" | head -1 || echo "null")
    fi
fi

# 3. Check Heterogeneity Plot
PNG_FILE="$OUTPUT_DIR/heterogeneity_plot.png"
if [ -f "$PNG_FILE" ]; then
    PNG_MTIME=$(stat -c %Y "$PNG_FILE" 2>/dev/null || echo "0")
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_EXISTS="true"
        PNG_SIZE_BYTES=$(stat -c %s "$PNG_FILE")
    fi
fi

# 4. Check Script Modification
SCRIPT_FILE="/home/ga/RProjects/gasoline_analysis.R"
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
        
        # Check if plm was actually used in the script
        if grep -q "plm" "$SCRIPT_FILE"; then
            SCRIPT_CONTAINS_PLM="true"
        else
            SCRIPT_CONTAINS_PLM="false"
        fi
    fi
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "csv_exists": $CSV_EXISTS,
    "txt_exists": $TXT_EXISTS,
    "png_exists": $PNG_EXISTS,
    "script_modified": $SCRIPT_MODIFIED,
    "fe_price_elasticity": $FE_PRICE_ELASTICITY,
    "hausman_pval": $HAUSMAN_PVAL,
    "png_size_bytes": $PNG_SIZE_BYTES,
    "script_contains_plm": "${SCRIPT_CONTAINS_PLM:-false}",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe copy to avoid permission issues
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="