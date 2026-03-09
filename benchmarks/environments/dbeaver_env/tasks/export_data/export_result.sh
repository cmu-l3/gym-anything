#!/bin/bash
# Export script for export_data task
# Validates actual customer data content, not just keywords

echo "=== Exporting Export Data Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Expected values
EXPECTED_CUSTOMERS=59
EXPECTED_PATH="/home/ga/Documents/exports/customers_export.csv"

# Known customer data for validation (multiple records to prevent keyword stuffing)
# Format: CustomerID|FirstName|LastName|Email
KNOWN_CUSTOMERS=(
    "1|Luís|Gonçalves|luisg@embraer.com.br"
    "2|Leonie|Köhler|leonekohler@surfeu.de"
    "3|François|Tremblay|ftremblay@gmail.com"
    "10|Eduardo|Martins|eduardo@woodstock.com.br"
    "20|Dan|Miller|dmiller@comcast.com"
    "30|Edward|Francis|edfrancis@yachoo.ca"
    "50|Enrique|Muñoz|enrique_munoz@mail.com"
    "59|Puja|Srivastava|puja_srivastava@yahoo.in"
)

# Initialize variables
FILE_EXISTS="false"
CORRECT_PATH="false"
FILE_SIZE=0
ROW_COUNT=0
COLUMN_COUNT=0
HAS_ALL_COLUMNS="false"
HAS_CUSTOMERID="false"
HAS_FIRSTNAME="false"
HAS_LASTNAME="false"
HAS_EMAIL="false"
CREATED_RECENTLY="false"
CONTENT_VALID="false"
CUSTOMERS_MATCHED=0
ACTUAL_PATH=""

echo "Checking export file at EXACT path: $EXPECTED_PATH"

# STRICT: Only check the exact expected path - NO FALLBACK
if [ -f "$EXPECTED_PATH" ]; then
    FILE_EXISTS="true"
    CORRECT_PATH="true"
    ACTUAL_PATH="$EXPECTED_PATH"
    FILE_SIZE=$(get_file_size "$EXPECTED_PATH")
    echo "Export file found at correct path, size: $FILE_SIZE bytes"

    # Count rows (excluding header)
    TOTAL_LINES=$(wc -l < "$EXPECTED_PATH")
    ROW_COUNT=$((TOTAL_LINES - 1))
    echo "Total lines: $TOTAL_LINES (rows: $ROW_COUNT)"

    # Count columns
    COLUMN_COUNT=$(head -1 "$EXPECTED_PATH" | awk -F',' '{print NF}')
    echo "Columns: $COLUMN_COUNT"

    # Get and validate header
    HEADER=$(head -1 "$EXPECTED_PATH")
    echo "Header: $HEADER"

    # Check for REQUIRED columns (must have ALL of these)
    if echo "$HEADER" | grep -qi "customerid"; then
        HAS_CUSTOMERID="true"
    fi
    if echo "$HEADER" | grep -qi "firstname"; then
        HAS_FIRSTNAME="true"
    fi
    if echo "$HEADER" | grep -qi "lastname"; then
        HAS_LASTNAME="true"
    fi
    if echo "$HEADER" | grep -qi "email"; then
        HAS_EMAIL="true"
    fi

    # Header is valid only if ALL required columns are present
    if [ "$HAS_CUSTOMERID" = "true" ] && [ "$HAS_FIRSTNAME" = "true" ] && \
       [ "$HAS_LASTNAME" = "true" ] && [ "$HAS_EMAIL" = "true" ]; then
        HAS_ALL_COLUMNS="true"
        echo "Header valid: Contains all required columns"
    else
        echo "Header INVALID: Missing required columns"
    fi

    # Check if file was created recently (within last 10 minutes)
    CREATED_RECENTLY=$(file_created_recently "$EXPECTED_PATH" 600)
    echo "Created recently: $CREATED_RECENTLY"

    # ROBUST CONTENT VALIDATION: Check multiple known customer records
    # This prevents an attacker from just adding keywords
    FILE_CONTENT=$(cat "$EXPECTED_PATH")

    echo "Validating customer records..."
    for known_customer in "${KNOWN_CUSTOMERS[@]}"; do
        # Parse the known customer data
        IFS='|' read -r cust_id first_name last_name email <<< "$known_customer"

        # Check if this customer's data appears in the file
        # Must match at least email (unique identifier)
        if echo "$FILE_CONTENT" | grep -qi "$email"; then
            CUSTOMERS_MATCHED=$((CUSTOMERS_MATCHED + 1))
            echo "  Matched customer $cust_id: $first_name $last_name ($email)"
        fi
    done

    echo "Matched $CUSTOMERS_MATCHED of ${#KNOWN_CUSTOMERS[@]} known customers"

    # Content is valid only if we match at least 5 of the known customers
    # This ensures it's actual customers table data, not fake data
    MIN_CUSTOMERS_REQUIRED=5
    if [ "$CUSTOMERS_MATCHED" -ge "$MIN_CUSTOMERS_REQUIRED" ]; then
        CONTENT_VALID="true"
        echo "Content validation: PASSED ($CUSTOMERS_MATCHED customers verified)"
    else
        echo "Content validation: FAILED (only $CUSTOMERS_MATCHED of $MIN_CUSTOMERS_REQUIRED required)"
    fi

    # Show first few lines
    echo ""
    echo "First 5 lines of export:"
    head -5 "$EXPECTED_PATH"
else
    echo "Export file NOT found at expected path: $EXPECTED_PATH"
    echo ""
    echo "NOTE: The task requires exporting to exactly: $EXPECTED_PATH"
    echo "Files at other paths or with different names will NOT be accepted."

    # List what's in the exports directory for debugging
    echo ""
    echo "Contents of exports directory:"
    ls -la /home/ga/Documents/exports/ 2>/dev/null || echo "Directory does not exist"
fi

# Check DBeaver state
DBEAVER_RUNNING=$(is_dbeaver_running)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/export_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "correct_path": $CORRECT_PATH,
    "actual_path": "$ACTUAL_PATH",
    "expected_path": "$EXPECTED_PATH",
    "file_size_bytes": $FILE_SIZE,
    "row_count": $ROW_COUNT,
    "column_count": $COLUMN_COUNT,
    "has_all_columns": $HAS_ALL_COLUMNS,
    "has_customerid_column": $HAS_CUSTOMERID,
    "has_firstname_column": $HAS_FIRSTNAME,
    "has_lastname_column": $HAS_LASTNAME,
    "has_email_column": $HAS_EMAIL,
    "content_valid": $CONTENT_VALID,
    "customers_matched": $CUSTOMERS_MATCHED,
    "min_customers_required": $MIN_CUSTOMERS_REQUIRED,
    "created_recently": $CREATED_RECENTLY,
    "expected_row_count": $EXPECTED_CUSTOMERS,
    "dbeaver_running": $DBEAVER_RUNNING,
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
