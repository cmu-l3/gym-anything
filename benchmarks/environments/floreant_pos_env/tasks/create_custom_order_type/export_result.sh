#!/bin/bash
echo "=== Exporting Create Custom Order Type Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query the Derby database for the 'Curbside' order type
# We need to stop Floreant briefly or use a query that works while running (Derby embedded mode usually locks the DB)
# For reliability, we will kill Floreant before querying.
kill_floreant

echo "Querying database for 'Curbside' order type..."
QUERY_OUTPUT="/tmp/ordertype_query.txt"
IJ_SCRIPT="/tmp/query_ordertype.sql"

# Create SQL script to select the relevant columns
# Note: Column names based on standard Floreant POS schema
cat > "$IJ_SCRIPT" <<EOF
CONNECT 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
SELECT NAME, SHOW_TABLE_SELECTION, SHOW_GUEST_SELECTION, REQUIRED_CUSTOMER_DATA, PREPAID FROM ORDER_TYPE WHERE NAME = 'Curbside';
DISCONNECT;
EXIT;
EOF

# Run the query
java -Dderby.system.home=/opt/floreantpos/database/derby-server \
     -cp "/opt/floreantpos/lib/*" \
     org.apache.derby.tools.ij "$IJ_SCRIPT" > "$QUERY_OUTPUT" 2>&1

echo "Database query complete. Parsing results..."

# 3. Parse the output into JSON
# Sample ij output:
# NAME                |SHOW_&|SHOW_&|REQUI&|PREPAID
# -------------------------------------------------
# Curbside            |0     |0     |1     |1
#
# 1 row selected

# Helper function to extract value for a column index (1-based) from the data row
# We look for the line starting with "Curbside"
DATA_ROW=$(grep "^Curbside" "$QUERY_OUTPUT" | head -1)

if [ -n "$DATA_ROW" ]; then
    ORDER_TYPE_EXISTS="true"
    # Extract values using awk (columns are pipe-delimited in ij output usually, or fixed width)
    # ij output is often fixed width or pipe separated depending on formatting.
    # Let's assume standard ij formatting. We will clean up the line.
    
    # Remove all whitespace
    CLEAN_ROW=$(echo "$DATA_ROW" | tr -d '[:space:]')
    
    # Check for specific patterns since parsing CLI table output can be brittle
    # We will simply check if the row contains the expected boolean flags in order if possible, 
    # OR we can generate a cleaner CSV export.
    
    # Let's try a CSV export approach for robustness
    CSV_SCRIPT="/tmp/query_ordertype_csv.sql"
    cat > "$CSV_SCRIPT" <<EOF
CONNECT 'jdbc:derby:/opt/floreantpos/database/derby-server/posdb';
CALL SYSCS_UTIL.SYSCS_EXPORT_QUERY('SELECT NAME, SHOW_TABLE_SELECTION, SHOW_GUEST_SELECTION, REQUIRED_CUSTOMER_DATA, PREPAID FROM ORDER_TYPE WHERE NAME = ''Curbside''', '/tmp/ordertype_export.csv', null, null, null);
DISCONNECT;
EXIT;
EOF
    
    rm -f /tmp/ordertype_export.csv
    java -Dderby.system.home=/opt/floreantpos/database/derby-server \
         -cp "/opt/floreantpos/lib/*" \
         org.apache.derby.tools.ij "$CSV_SCRIPT" > /dev/null 2>&1
         
    if [ -f /tmp/ordertype_export.csv ]; then
        # Read the CSV (format: "Curbside",0,0,1,1)
        CONTENT=$(cat /tmp/ordertype_export.csv)
        # Remove quotes
        CONTENT=$(echo "$CONTENT" | tr -d '"')
        
        NAME=$(echo "$CONTENT" | cut -d',' -f1)
        SHOW_TABLE=$(echo "$CONTENT" | cut -d',' -f2)
        SHOW_GUEST=$(echo "$CONTENT" | cut -d',' -f3)
        REQ_DATA=$(echo "$CONTENT" | cut -d',' -f4)
        PREPAID=$(echo "$CONTENT" | cut -d',' -f5)
    else
        # Fallback if export fails (e.g. permission issues), rely on previous existence check
        ORDER_TYPE_EXISTS="false" 
    fi
else
    ORDER_TYPE_EXISTS="false"
fi

# Set defaults if not found
NAME=${NAME:-""}
SHOW_TABLE=${SHOW_TABLE:-0}
SHOW_GUEST=${SHOW_GUEST:-0}
REQ_DATA=${REQ_DATA:-0}
PREPAID=${PREPAID:-0}

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "order_type_exists": $ORDER_TYPE_EXISTS,
    "name": "$NAME",
    "show_table_selection": $SHOW_TABLE,
    "show_guest_selection": $SHOW_GUEST,
    "required_customer_data": $REQ_DATA,
    "prepaid": $PREPAID,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="