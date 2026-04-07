#!/bin/bash
echo "=== Exporting Annotate Suspicious Events results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# =====================================================
# Database Verification
# =====================================================
# Since the exact table for "Notes" can vary by ELA version (e.g., EventNotes, AlertNotes),
# and schema documentation is internal, we use a robust method:
# Dump the database content and grep for the unique string "CASE-999".
# This proves the data was persisted to the DB.

echo "Querying database for note content..."
NOTE_CONTENT="CASE-999"
DB_DUMP_FILE="/tmp/ela_db_dump.txt"

# Use pg_dump to dump the 'eventlog' database (schema + data)
# We use the credentials defined in task_utils (admin/admin is web, but DB uses specific user)
# task_utils.sh defines ela_db_query, but here we might want pg_dump.
# We'll try a direct SQL query first if we can guess the table, otherwise dump.

# Attempt 1: Check if "CASE-999" exists anywhere in text columns
# We'll use pg_dump as a "grep search" engine for the DB.
PGPASSWORD="eventloganalyzer" /opt/ManageEngine/EventLog/pgsql/bin/pg_dump \
    -h localhost -p 33335 -U eventloganalyzer -d eventlog \
    --data-only --inserts > "$DB_DUMP_FILE" 2>/dev/null || true

if [ ! -s "$DB_DUMP_FILE" ]; then
    # Fallback for standard postgres port if bundled one fails
    PGPASSWORD="eventloganalyzer" pg_dump \
        -h localhost -p 5432 -U postgres -d eventlog \
        --data-only --inserts > "$DB_DUMP_FILE" 2>/dev/null || true
fi

# Check if our note exists in the dump
if grep -q "CASE-999" "$DB_DUMP_FILE"; then
    echo "Found note in database!"
    NOTE_FOUND="true"
    # Extract the line for context (debugging)
    NOTE_CONTEXT=$(grep "CASE-999" "$DB_DUMP_FILE" | head -1 | cut -c 1-100)
else
    echo "Note NOT found in database."
    NOTE_FOUND="false"
    NOTE_CONTEXT=""
fi

# Clean up large dump file
rm -f "$DB_DUMP_FILE"

# =====================================================
# Application State
# =====================================================
APP_RUNNING="false"
if pgrep -f "ManageEngine" >/dev/null; then
    APP_RUNNING="true"
fi

# =====================================================
# Create Result JSON
# =====================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "note_found_in_db": $NOTE_FOUND,
    "note_context": "$(echo $NOTE_CONTEXT | sed 's/"/\\"/g')",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="