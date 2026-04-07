#!/bin/bash
echo "=== Exporting MICE Task Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Files Existence and Timestamps
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "exists_but_old"
        fi
    else
        echo "false"
    fi
}

FILE_MISSING_PATTERN=$(check_file "/home/ga/RProjects/output/missing_pattern.png")
FILE_DIAGNOSTICS=$(check_file "/home/ga/RProjects/output/imputation_diagnostics.png")
FILE_COMPARISON=$(check_file "/home/ga/RProjects/output/model_comparison.csv")
FILE_SCRIPT=$(check_file "/home/ga/RProjects/imputation_analysis.R")

# 3. Check if 'mice' package is installed
# We run a quick R command to check availability
MICE_INSTALLED=$(R --slave -e "cat(requireNamespace('mice', quietly=TRUE))" 2>/dev/null)

# 4. Parse the CSV content if it exists
# We extract the 'Temp' coefficient for validation
CSV_CONTENT_JSON="null"
if [ "$FILE_COMPARISON" = "true" ]; then
    # Convert CSV to simple JSON object for the Temp row
    # Expecting columns: term, estimate_naive, estimate_pooled, ...
    CSV_CONTENT_JSON=$(python3 -c "
import csv, json
import sys

try:
    data = {}
    with open('/home/ga/RProjects/output/model_comparison.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Normalize key names to lowercase to be robust
            row_norm = {k.lower().strip(): v for k, v in row.items()}
            term = row_norm.get('term', '').replace('\"', '').strip()
            
            if 'temp' in term.lower():
                data['temp_naive'] = row_norm.get('estimate_naive')
                data['temp_pooled'] = row_norm.get('estimate_pooled')
                data['se_naive'] = row_norm.get('std_error_naive')
                data['se_pooled'] = row_norm.get('std_error_pooled')
            
            # Check for column presence
            data['columns'] = list(row_norm.keys())

    print(json.dumps(data))
except Exception as e:
    print(json.dumps({'error': str(e)}))
")
fi

# 5. Check if R script uses 'mice', 'pool', 'with'
SCRIPT_CONTENT_MATCHES="false"
if [ -f "/home/ga/RProjects/imputation_analysis.R" ]; then
    if grep -q "mice(" "/home/ga/RProjects/imputation_analysis.R" && \
       grep -q "pool(" "/home/ga/RProjects/imputation_analysis.R"; then
        SCRIPT_CONTENT_MATCHES="true"
    fi
fi

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/mice_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "mice_installed": "$MICE_INSTALLED",
    "files": {
        "missing_pattern_png": "$FILE_MISSING_PATTERN",
        "diagnostics_png": "$FILE_DIAGNOSTICS",
        "comparison_csv": "$FILE_COMPARISON",
        "script_r": "$FILE_SCRIPT"
    },
    "script_content_valid": $SCRIPT_CONTENT_MATCHES,
    "csv_data": $CSV_CONTENT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json