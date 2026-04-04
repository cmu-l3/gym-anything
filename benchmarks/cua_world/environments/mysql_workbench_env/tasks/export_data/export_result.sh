#!/bin/bash
# Export script for export_data task

echo "=== Exporting Export Data Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Expected values
EXPECTED_CITIES=248
EXPECTED_OUTPUT="/home/ga/Documents/exports/japan_cities.csv"

# Initialize variables
WORKBENCH_RUNNING=$(is_workbench_running)
EXPORT_SUCCESSFUL="false"
OUTPUT_FILE_EXISTS="false"
OUTPUT_ROW_COUNT=0
CORRECT_CITY_COUNT="false"
CITIES_FOUND=""
KNOWN_CITIES_MATCHED=0
DB_VALIDATED_COUNT=0
HAS_CORRECT_COLUMNS="false"
COLUMN_COUNT=0

# Known Japanese cities that should appear
KNOWN_CITIES=("Tokyo" "Osaka" "Nagoya" "Sapporo" "Kobe" "Fukuoka" "Kawasaki" "Hiroshima")

echo "Checking for export output file at: $EXPECTED_OUTPUT"

# Do NOT accept alternative file names - require exact path
# This prevents gaming by pre-creating files
if [ ! -f "$EXPECTED_OUTPUT" ]; then
    echo "Expected output file not found: $EXPECTED_OUTPUT"
    echo "Checking for similar files (for debugging only):"
    ls -la /home/ga/Documents/exports/*.csv 2>/dev/null || echo "No CSV files in exports directory"
fi

# PRIMARY CHECK: Verify the output file exists with correct content
if [ -f "$EXPECTED_OUTPUT" ]; then
    OUTPUT_FILE_EXISTS="true"
    echo "Output file found: $EXPECTED_OUTPUT"

    # Count rows (excluding header)
    TOTAL_LINES=$(wc -l < "$EXPECTED_OUTPUT")
    OUTPUT_ROW_COUNT=$((TOTAL_LINES - 1))
    echo "Output has $OUTPUT_ROW_COUNT data rows"

    # Check column count from header
    HEADER_LINE=$(head -1 "$EXPECTED_OUTPUT")
    COLUMN_COUNT=$(echo "$HEADER_LINE" | awk -F',' '{print NF}')
    echo "Column count: $COLUMN_COUNT"

    # Check if we have expected columns (5 columns for city table)
    if [ "$COLUMN_COUNT" -ge 4 ] && [ "$COLUMN_COUNT" -le 6 ]; then
        HAS_CORRECT_COLUMNS="true"
        echo "Column structure appears correct"
    fi

    # Check if header contains expected column names
    if echo "$HEADER_LINE" | grep -qi "ID\|Name\|CountryCode\|District\|Population"; then
        echo "Header contains expected column names"
    fi

    # Check if row count matches expected (allow some tolerance)
    if [ "$OUTPUT_ROW_COUNT" -ge 240 ] && [ "$OUTPUT_ROW_COUNT" -le 256 ]; then
        CORRECT_CITY_COUNT="true"
        echo "City count is correct (expected ~248, got $OUTPUT_ROW_COUNT)"
    fi

    # Read file content (handle various encodings)
    FILE_CONTENT=$(cat "$EXPECTED_OUTPUT" | tr '[:upper:]' '[:lower:]')

    # Verify known cities are present
    for city in "${KNOWN_CITIES[@]}"; do
        city_lower=$(echo "$city" | tr '[:upper:]' '[:lower:]')
        if echo "$FILE_CONTENT" | grep -qF "$city_lower"; then
            KNOWN_CITIES_MATCHED=$((KNOWN_CITIES_MATCHED + 1))
            CITIES_FOUND="${CITIES_FOUND}${city}, "
        fi
    done

    echo "Matched $KNOWN_CITIES_MATCHED of ${#KNOWN_CITIES[@]} known cities"
    echo "Found cities: $CITIES_FOUND"

    # ANTI-GAMING: Validate against actual database
    echo ""
    echo "Validating CSV content against database..."

    # Find which column contains city names by checking header
    NAME_COL=2  # Default
    IFS=',' read -ra HEADERS <<< "$HEADER_LINE"
    for i in "${!HEADERS[@]}"; do
        header_clean=$(echo "${HEADERS[$i]}" | sed 's/^"//;s/"$//' | tr '[:upper:]' '[:lower:]' | xargs)
        if [ "$header_clean" = "name" ]; then
            NAME_COL=$((i + 1))
            echo "Found Name column at position $NAME_COL"
            break
        fi
    done

    while IFS= read -r line; do
        # Extract city name from the identified column
        city_name=$(echo "$line" | cut -d',' -f"$NAME_COL" | sed 's/^"//;s/"$//' | xargs)
        if [ -n "$city_name" ] && [ "$city_name" != "Name" ] && [ ${#city_name} -gt 1 ]; then
            # Check if this city exists in Japan
            db_check=$(world_query "SELECT COUNT(*) FROM city WHERE Name LIKE '%$city_name%' AND CountryCode = 'JPN'" 2>/dev/null || echo "0")
            if [ "$db_check" -ge 1 ]; then
                DB_VALIDATED_COUNT=$((DB_VALIDATED_COUNT + 1))
            fi
        fi
        # Only check first 20 entries for performance
        if [ "$DB_VALIDATED_COUNT" -ge 20 ]; then
            break
        fi
    done < <(tail -n +2 "$EXPECTED_OUTPUT" | head -25)

    echo "Database validated $DB_VALIDATED_COUNT city entries"

    # Export is considered successful if we have correct data
    if [ "$CORRECT_CITY_COUNT" = "true" ] && [ "$KNOWN_CITIES_MATCHED" -ge 3 ] && [ "$DB_VALIDATED_COUNT" -ge 10 ]; then
        EXPORT_SUCCESSFUL="true"
        echo "Export VERIFIED via output file and database validation"
    fi

    # Show file content
    echo ""
    echo "Output file contents (first 10 lines):"
    head -10 "$EXPECTED_OUTPUT"
else
    echo "Output file NOT found at expected path"
    echo ""
    echo "Contents of exports directory:"
    ls -la /home/ga/Documents/exports/ 2>/dev/null || echo "Directory does not exist"
fi

# Get actual count from database for reference
ACTUAL_DB_COUNT=$(world_query "SELECT COUNT(*) FROM city WHERE CountryCode = 'JPN'")

# Escape strings for JSON
CITIES_FOUND_ESCAPED=$(echo "$CITIES_FOUND" | sed 's/"/\\"/g')
HEADER_ESCAPED=$(echo "$HEADER_LINE" | sed 's/"/\\"/g' | head -c 200)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/export_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "workbench_running": $WORKBENCH_RUNNING,
    "export_successful": $EXPORT_SUCCESSFUL,
    "output_file_exists": $OUTPUT_FILE_EXISTS,
    "output_file_path": "$EXPECTED_OUTPUT",
    "output_row_count": $OUTPUT_ROW_COUNT,
    "correct_city_count": $CORRECT_CITY_COUNT,
    "known_cities_matched": $KNOWN_CITIES_MATCHED,
    "cities_found": "$CITIES_FOUND_ESCAPED",
    "db_validated_count": $DB_VALIDATED_COUNT,
    "actual_db_count": $ACTUAL_DB_COUNT,
    "column_count": $COLUMN_COUNT,
    "has_correct_columns": $HAS_CORRECT_COLUMNS,
    "header_line": "$HEADER_ESCAPED",
    "expected_city_count": $EXPECTED_CITIES,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/export_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/export_result.json
chmod 666 /tmp/export_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/export_result.json"
cat /tmp/export_result.json

echo ""
echo "=== Export Complete ==="
