#!/bin/bash
# Export script for run_sql_query task

echo "=== Exporting Run SQL Query Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Expected values
EXPECTED_FILMS=336
EXPECTED_OUTPUT="/home/ga/Documents/exports/expensive_films.csv"

# Initialize variables
WORKBENCH_RUNNING=$(is_workbench_running)
QUERY_EXECUTED="false"
OUTPUT_FILE_EXISTS="false"
OUTPUT_ROW_COUNT=0
CORRECT_FILM_COUNT="false"
FILMS_FOUND=""
KNOWN_FILMS_MATCHED=0
DB_VALIDATED_COUNT=0

# Known film titles that should appear (these have rental_rate > 2.99 = 4.99)
KNOWN_FILMS=("ACE GOLDFINGER" "AIRPLANE SIERRA" "AIRPORT POLLOCK" "ALADDIN CALENDAR" "ALI FOREVER" "AMELIE HELLFIGHTERS" "AMERICAN CIRCUS")

echo "Checking for query output file at: $EXPECTED_OUTPUT"

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

    # Check if row count matches expected (allow some tolerance)
    if [ "$OUTPUT_ROW_COUNT" -ge 330 ] && [ "$OUTPUT_ROW_COUNT" -le 340 ]; then
        CORRECT_FILM_COUNT="true"
        echo "Film count is correct (expected ~336, got $OUTPUT_ROW_COUNT)"
    fi

    # Read file content (convert to lowercase for comparison)
    FILE_CONTENT=$(cat "$EXPECTED_OUTPUT" | tr '[:upper:]' '[:lower:]')

    # Verify known films are present
    for film in "${KNOWN_FILMS[@]}"; do
        film_lower=$(echo "$film" | tr '[:upper:]' '[:lower:]')
        if echo "$FILE_CONTENT" | grep -qF "$film_lower"; then
            KNOWN_FILMS_MATCHED=$((KNOWN_FILMS_MATCHED + 1))
            FILMS_FOUND="${FILMS_FOUND}${film}, "
        fi
    done

    echo "Matched $KNOWN_FILMS_MATCHED of ${#KNOWN_FILMS[@]} known films"
    echo "Found films: $FILMS_FOUND"

    # ANTI-GAMING: Validate against actual database
    # Find title column dynamically (handles different column orders)
    echo ""
    echo "Validating CSV content against database..."

    HEADER_LINE=$(head -1 "$EXPECTED_OUTPUT")
    TITLE_COL=1  # Default
    IFS=',' read -ra HEADERS <<< "$HEADER_LINE"
    for i in "${!HEADERS[@]}"; do
        header_clean=$(echo "${HEADERS[$i]}" | sed 's/^"//;s/"$//' | tr '[:upper:]' '[:lower:]' | xargs)
        if [ "$header_clean" = "title" ]; then
            TITLE_COL=$((i + 1))
            echo "Found title column at position $TITLE_COL"
            break
        fi
    done

    while IFS= read -r line; do
        # Extract title from the identified column
        title=$(echo "$line" | cut -d',' -f"$TITLE_COL" | sed 's/^"//;s/"$//' | xargs)
        if [ -n "$title" ] && [ "$title" != "title" ] && [ ${#title} -gt 1 ]; then
            # Check if this film exists with rental_rate > 2.99
            db_check=$(sakila_query "SELECT COUNT(*) FROM film WHERE LOWER(title) = LOWER('$title') AND rental_rate > 2.99" 2>/dev/null || echo "0")
            if [ "$db_check" = "1" ]; then
                DB_VALIDATED_COUNT=$((DB_VALIDATED_COUNT + 1))
            fi
        fi
        # Only check first 20 entries for performance
        if [ "$DB_VALIDATED_COUNT" -ge 20 ]; then
            break
        fi
    done < <(tail -n +2 "$EXPECTED_OUTPUT" | head -25)

    echo "Database validated $DB_VALIDATED_COUNT film entries"

    # Query is considered executed if we have the output file with correct data
    if [ "$CORRECT_FILM_COUNT" = "true" ] && [ "$KNOWN_FILMS_MATCHED" -ge 3 ] && [ "$DB_VALIDATED_COUNT" -ge 10 ]; then
        QUERY_EXECUTED="true"
        echo "Query execution VERIFIED via output file and database validation"
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

# SECONDARY CHECK: Check if query exists in Workbench history/scripts
SQL_QUERY=""
SQL_FILE_FOUND="false"

# Check snap config location for query history
SNAP_DATA="/home/ga/snap/mysql-workbench-community/current"
if [ -d "$SNAP_DATA" ]; then
    # Look for SQL files
    for sql_file in "$SNAP_DATA"/*.sql; do
        if [ -f "$sql_file" ]; then
            if grep -qi "rental_rate\|film" "$sql_file" 2>/dev/null; then
                SQL_QUERY=$(cat "$sql_file" | head -20)
                SQL_FILE_FOUND="true"
                echo "Found SQL file with relevant content: $sql_file"
                break
            fi
        fi
    done
fi

# Check user's SQL scripts directory
for sql_file in /home/ga/Documents/sql_scripts/*.sql; do
    if [ -f "$sql_file" ] && [ "$SQL_FILE_FOUND" = "false" ]; then
        if grep -qi "rental_rate.*2.99\|WHERE.*rental" "$sql_file" 2>/dev/null; then
            SQL_QUERY=$(cat "$sql_file" | head -20)
            SQL_FILE_FOUND="true"
            echo "Found SQL file: $sql_file"
            break
        fi
    fi
done

# Escape SQL query for JSON
SQL_QUERY_ESCAPED=$(echo "$SQL_QUERY" | tr '\n' ' ' | sed 's/"/\\"/g' | head -c 500)
FILMS_FOUND_ESCAPED=$(echo "$FILMS_FOUND" | sed 's/"/\\"/g')

# Get actual count from database for reference
ACTUAL_DB_COUNT=$(sakila_query "SELECT COUNT(*) FROM film WHERE rental_rate > 2.99")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/query_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "workbench_running": $WORKBENCH_RUNNING,
    "query_executed": $QUERY_EXECUTED,
    "output_file_exists": $OUTPUT_FILE_EXISTS,
    "output_file_path": "$EXPECTED_OUTPUT",
    "output_row_count": $OUTPUT_ROW_COUNT,
    "correct_film_count": $CORRECT_FILM_COUNT,
    "known_films_matched": $KNOWN_FILMS_MATCHED,
    "films_found": "$FILMS_FOUND_ESCAPED",
    "db_validated_count": $DB_VALIDATED_COUNT,
    "actual_db_count": $ACTUAL_DB_COUNT,
    "sql_file_found": $SQL_FILE_FOUND,
    "sql_query": "$SQL_QUERY_ESCAPED",
    "expected_film_count": $EXPECTED_FILMS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/query_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/query_result.json
chmod 666 /tmp/query_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/query_result.json"
cat /tmp/query_result.json

echo ""
echo "=== Export Complete ==="
