#!/bin/bash
set -e
echo "=== Exporting add_cooking_instruction results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot (Evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Stop Application (Critical to flush DB to disk)
echo "Stopping Floreant POS to flush database..."
kill_floreant
sleep 3

# 3. Analyze Database for Target Strings
# Derby stores data in 'seg0' directory files. Grep is effective for string verification.
DB_SEG_DIR=$(find /opt/floreantpos/database -name "seg0" -type d 2>/dev/null | head -1)

FOUND_NO_ONIONS="false"
FOUND_EXTRA_CRISPY="false"

if [ -n "$DB_SEG_DIR" ]; then
    echo "Searching database segments in $DB_SEG_DIR..."
    
    # Check "No Onions"
    if grep -rla "No Onions" "$DB_SEG_DIR" > /dev/null; then
        FOUND_NO_ONIONS="true"
        echo "Found 'No Onions' in database."
    fi
    
    # Check "Extra Crispy"
    if grep -rla "Extra Crispy" "$DB_SEG_DIR" > /dev/null; then
        FOUND_EXTRA_CRISPY="true"
        echo "Found 'Extra Crispy' in database."
    fi
else
    echo "ERROR: Database segment directory not found."
fi

# 4. Verify Database Modification (Anti-gaming)
DB_MODIFIED="false"
if [ -n "$DB_SEG_DIR" ] && [ -f /tmp/initial_db_checksums.txt ]; then
    find "$DB_SEG_DIR" -type f -exec md5sum {} \; | sort > /tmp/final_db_checksums.txt
    if ! diff -q /tmp/initial_db_checksums.txt /tmp/final_db_checksums.txt > /dev/null; then
        DB_MODIFIED="true"
        echo "Database modification detected."
    else
        echo "WARNING: Database files identical to start."
    fi
fi

# 5. SQL Verification (Secondary/Backup)
# Try to use Derby tools to verify structurally if possible
SQL_VERIFIED_NO_ONIONS="false"
SQL_VERIFIED_EXTRA_CRISPY="false"

# Locate Derby jars
DERBY_JAR=$(find /opt/floreantpos -name "derby.jar" -o -name "derby*.jar" | head -1)
DB_PATH=$(find /opt/floreantpos/database -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)

if [ -n "$DERBY_JAR" ] && [ -n "$DB_PATH" ]; then
    echo "Attempting SQL verification..."
    # Create SQL script
    cat > /tmp/verify_cooking.sql << EOF
CONNECT 'jdbc:derby:${DB_PATH};create=false';
SELECT * FROM COOKING_INSTRUCTION;
EXIT;
EOF
    
    # Run ij
    export CLASSPATH="$DERBY_JAR:$CLASSPATH"
    # Timeout after 15s to prevent hanging
    timeout 15 java org.apache.derby.tools.ij /tmp/verify_cooking.sql > /tmp/sql_output.txt 2>&1 || true
    
    if [ -f /tmp/sql_output.txt ]; then
        if grep -q "No Onions" /tmp/sql_output.txt; then
            SQL_VERIFIED_NO_ONIONS="true"
        fi
        if grep -q "Extra Crispy" /tmp/sql_output.txt; then
            SQL_VERIFIED_EXTRA_CRISPY="true"
        fi
    fi
fi

# 6. Generate Result JSON
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "found_no_onions": $FOUND_NO_ONIONS,
    "found_extra_crispy": $FOUND_EXTRA_CRISPY,
    "sql_verified_no_onions": $SQL_VERIFIED_NO_ONIONS,
    "sql_verified_extra_crispy": $SQL_VERIFIED_EXTRA_CRISPY,
    "db_modified": $DB_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions for extraction
chmod 644 /tmp/task_result.json
chmod 644 /tmp/task_final.png

echo "Result generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="