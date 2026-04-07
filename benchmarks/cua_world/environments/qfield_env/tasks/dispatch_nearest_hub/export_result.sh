#!/system/bin/sh
# Export script for dispatch_nearest_hub task.
# Extracts the GeoPackage state for verification.

echo "=== Exporting results for dispatch_nearest_hub ==="

# Define paths
PACKAGE="ch.opengis.qfield"
GPKG_PATH="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
RESULT_JSON="/sdcard/task_result.json"

# 1. Stop QField to ensure WAL (Write-Ahead Log) is flushed to the main DB file
echo "Stopping QField to flush database..."
am force-stop $PACKAGE
sleep 3

# 2. Verification Data Extraction
# We need to extract the 'notes' and 'name' of the updated features.
# Since we are inside the Android emulator, we use the system 'sqlite3' binary.

echo "Querying GeoPackage..."

# Check if sqlite3 is available
if command -v sqlite3 >/dev/null 2>&1; then
    # Create a temporary SQL script
    echo ".headers off" > /sdcard/query.sql
    echo ".mode json" >> /sdcard/query.sql
    
    # Query: Find any capital with 'DISPATCHING' in notes
    echo "SELECT name, notes FROM world_capitals WHERE notes LIKE '%DISPATCHING%';" >> /sdcard/query.sql
    
    # Execute query
    MATCHES=$(sqlite3 "$GPKG_PATH" < /sdcard/query.sql)
    
    # Also get file modification time
    FILE_MOD_TIME=$(stat -c %Y "$GPKG_PATH")
    START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
    
    # If no matches, output empty array
    if [ -z "$MATCHES" ]; then
        MATCHES="[]"
    fi
    
    # Construct JSON manually since we might be in a restricted shell
    echo "{" > "$RESULT_JSON"
    echo "  \"matches\": $MATCHES," >> "$RESULT_JSON"
    echo "  \"file_mod_time\": $FILE_MOD_TIME," >> "$RESULT_JSON"
    echo "  \"start_time\": $START_TIME," >> "$RESULT_JSON"
    echo "  \"gpkg_path\": \"$GPKG_PATH\"" >> "$RESULT_JSON"
    echo "}" >> "$RESULT_JSON"
    
else
    echo "ERROR: sqlite3 not found in environment."
    # Fallback: We will signal the verifier to download the whole GPKG
    echo "{" > "$RESULT_JSON"
    echo "  \"error\": \"sqlite3_missing\"," >> "$RESULT_JSON"
    echo "  \"gpkg_path\": \"$GPKG_PATH\"" >> "$RESULT_JSON"
    echo "}" >> "$RESULT_JSON"
fi

# 3. Copy the GeoPackage itself to a staging area for the verifier to pull
# (This is the most robust method: analyze the DB on the host)
cp "$GPKG_PATH" /sdcard/output_world_survey.gpkg
chmod 666 /sdcard/output_world_survey.gpkg

echo "Export complete. Result JSON and GPKG saved."
cat "$RESULT_JSON"