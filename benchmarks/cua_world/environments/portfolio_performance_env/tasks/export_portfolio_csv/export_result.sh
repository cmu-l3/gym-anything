#!/bin/bash
echo "=== Exporting export_portfolio_csv result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Search for exported CSV files
TARGET_DIR="/home/ga/Documents/PortfolioData"
CSV_FOUND="false"
CSV_FILE=""
CSV_ROW_COUNT=0
CSV_HEADER=""
CSV_HAS_DATE="false"
CSV_HAS_VALUE="false"
CSV_HAS_TYPE="false"
CSV_SAMPLE_ROWS=""

# Look for the expected file first
if [ -f "$TARGET_DIR/account_export.csv" ]; then
    CSV_FILE="$TARGET_DIR/account_export.csv"
    CSV_FOUND="true"
fi

# If not found, look for any new CSV files
if [ "$CSV_FOUND" = "false" ]; then
    for f in $(find "$TARGET_DIR" -name "*.csv" -newer /tmp/task_start_marker 2>/dev/null | sort -r); do
        # Skip our data files
        case "$f" in
            *aapl_historical*|*msft_historical*|*googl_historical*|*portfolio_transactions*|*account_deposits*)
                continue
                ;;
        esac
        CSV_FILE="$f"
        CSV_FOUND="true"
        break
    done
fi

# Also check home directory and Downloads
if [ "$CSV_FOUND" = "false" ]; then
    for d in /home/ga/Downloads /home/ga/Desktop /home/ga; do
        for f in $(find "$d" -maxdepth 2 -name "*.csv" -newer /tmp/task_start_marker 2>/dev/null | sort -r); do
            case "$f" in
                *aapl_historical*|*msft_historical*|*googl_historical*|*portfolio_transactions*|*account_deposits*)
                    continue
                    ;;
            esac
            CSV_FILE="$f"
            CSV_FOUND="true"
            break
        done
        [ "$CSV_FOUND" = "true" ] && break
    done
fi

# Analyze the CSV file if found
if [ "$CSV_FOUND" = "true" ] && [ -f "$CSV_FILE" ]; then
    CSV_ROW_COUNT=$(wc -l < "$CSV_FILE" 2>/dev/null || echo "0")
    CSV_HEADER=$(head -1 "$CSV_FILE" 2>/dev/null || echo "")

    # Check for expected columns (case-insensitive, support English and German locale)
    HEADER_LOWER=$(echo "$CSV_HEADER" | tr '[:upper:]' '[:lower:]')
    if echo "$HEADER_LOWER" | grep -qi "date\|datum"; then
        CSV_HAS_DATE="true"
    fi
    if echo "$HEADER_LOWER" | grep -qi "value\|amount\|betrag\|wert"; then
        CSV_HAS_VALUE="true"
    fi
    if echo "$HEADER_LOWER" | grep -qi "type\|typ"; then
        CSV_HAS_TYPE="true"
    fi

    # Get sample rows (first 5 data rows)
    CSV_SAMPLE_ROWS=$(head -6 "$CSV_FILE" 2>/dev/null | tail -5 || echo "")

    # Content verification: check for expected transaction types (English and German)
    CSV_CONTENT_LOWER=$(cat "$CSV_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    HAS_DEPOSIT="false"
    HAS_REMOVAL="false"
    if echo "$CSV_CONTENT_LOWER" | grep -qi "deposit\|einlage"; then
        HAS_DEPOSIT="true"
    fi
    if echo "$CSV_CONTENT_LOWER" | grep -qi "removal\|withdraw\|entnahme"; then
        HAS_REMOVAL="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json

result = {
    'csv_found': $( [ \"$CSV_FOUND\" = \"true\" ] && echo 'True' || echo 'False'),
    'csv_file': $(python3 -c "import json; print(json.dumps('$CSV_FILE'))" 2>/dev/null || echo '\"\"'),
    'csv_row_count': int('$CSV_ROW_COUNT'.strip()),
    'csv_header': $(python3 -c "import json; print(json.dumps(open('$CSV_FILE').readline().strip() if '$CSV_FOUND' == 'true' and '$CSV_FILE' else ''))" 2>/dev/null || echo '\"\"'),
    'has_date_column': $( [ \"$CSV_HAS_DATE\" = \"true\" ] && echo 'True' || echo 'False'),
    'has_value_column': $( [ \"$CSV_HAS_VALUE\" = \"true\" ] && echo 'True' || echo 'False'),
    'has_type_column': $( [ \"$CSV_HAS_TYPE\" = \"true\" ] && echo 'True' || echo 'False'),
    'sample_rows': $(python3 -c "
import json
rows = []
try:
    with open('$CSV_FILE') as f:
        lines = f.readlines()
        for line in lines[1:6]:
            rows.append(line.strip())
except:
    pass
print(json.dumps(rows))
" 2>/dev/null || echo '[]'),
    'has_deposit_entries': $( [ "$HAS_DEPOSIT" = "true" ] && echo 'True' || echo 'False'),
    'has_removal_entries': $( [ "$HAS_REMOVAL" = "true" ] && echo 'True' || echo 'False'),
    'timestamp': '$(date -Iseconds)'
}
with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

rm -f /tmp/export_csv_result.json 2>/dev/null || sudo rm -f /tmp/export_csv_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/export_csv_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/export_csv_result.json
chmod 666 /tmp/export_csv_result.json 2>/dev/null || sudo chmod 666 /tmp/export_csv_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/export_csv_result.json"
cat /tmp/export_csv_result.json
echo "=== Export complete ==="
