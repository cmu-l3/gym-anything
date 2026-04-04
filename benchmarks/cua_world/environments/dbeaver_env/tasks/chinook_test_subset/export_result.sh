#!/bin/bash
# Export script for chinook_test_subset task
# Verifies the created database structure, content, and referential integrity

echo "=== Exporting Chinook Test Subset Result ==="

source /workspace/scripts/task_utils.sh

# Paths
SOURCE_DB="/home/ga/Documents/databases/chinook.db"
TARGET_DB="/home/ga/Documents/databases/chinook_brazil_test.db"
SCRIPT_PATH="/home/ga/Documents/scripts/brazil_subset_extraction.sql"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check file existence
DB_EXISTS="false"
DB_SIZE=0
if [ -f "$TARGET_DB" ]; then
    DB_EXISTS="true"
    DB_SIZE=$(stat -c%s "$TARGET_DB" 2>/dev/null || echo 0)
fi

SCRIPT_EXISTS="false"
SCRIPT_SIZE=0
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat -c%s "$SCRIPT_PATH" 2>/dev/null || echo 0)
fi

# 2. Check DBeaver Connection
CONNECTION_EXISTS="false"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
if [ -f "$DBEAVER_CONFIG" ]; then
    if grep -qi "ChinookBrazilTest" "$DBEAVER_CONFIG"; then
        CONNECTION_EXISTS="true"
    fi
fi

# 3. Database Content Verification (using sqlite3)
# We will collect counts from the TARGET database
TARGET_COUNTS="{}"
RI_ERRORS="{}"
TABLE_CHECK="false"
CORRECT_CUSTOMERS="false"

if [ "$DB_EXISTS" = "true" ]; then
    # List tables
    TABLES=$(sqlite3 "$TARGET_DB" ".tables")
    
    # Check if all 9 required tables exist
    REQUIRED_TABLES=("customers" "employees" "invoices" "invoice_items" "tracks" "albums" "artists" "genres" "media_types")
    MISSING_TABLES=""
    for table in "${REQUIRED_TABLES[@]}"; do
        if ! echo "$TABLES" | grep -qi "$table"; then
            MISSING_TABLES="$MISSING_TABLES $table"
        fi
    done
    
    if [ -z "$MISSING_TABLES" ]; then
        TABLE_CHECK="true"
    fi

    # Get counts for all tables
    TARGET_COUNTS=$(sqlite3 "$TARGET_DB" "
        SELECT 'customers', COUNT(*) FROM customers UNION ALL
        SELECT 'employees', COUNT(*) FROM employees UNION ALL
        SELECT 'invoices', COUNT(*) FROM invoices UNION ALL
        SELECT 'invoice_items', COUNT(*) FROM invoice_items UNION ALL
        SELECT 'tracks', COUNT(*) FROM tracks UNION ALL
        SELECT 'albums', COUNT(*) FROM albums UNION ALL
        SELECT 'artists', COUNT(*) FROM artists UNION ALL
        SELECT 'genres', COUNT(*) FROM genres UNION ALL
        SELECT 'media_types', COUNT(*) FROM media_types;
    " | awk -F'|' '{printf "\"%s\": %s, ", $1, $2}' | sed 's/, $//')
    TARGET_COUNTS="{ $TARGET_COUNTS }"

    # Verify Customer Filter (Must be Brazil only)
    NON_BRAZIL_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers WHERE Country != 'Brazil';" 2>/dev/null || echo "0")
    BRAZIL_COUNT=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers WHERE Country = 'Brazil';" 2>/dev/null || echo "0")
    
    if [ "$NON_BRAZIL_COUNT" -eq 0 ] && [ "$BRAZIL_COUNT" -gt 0 ]; then
        CORRECT_CUSTOMERS="true"
    fi

    # Verify Referential Integrity (Orphan Checks)
    # Result should be 0 for all of these
    ORPHAN_INVOICES=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM invoices WHERE CustomerId NOT IN (SELECT CustomerId FROM customers);" 2>/dev/null || echo 0)
    ORPHAN_ITEMS=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM invoice_items WHERE InvoiceId NOT IN (SELECT InvoiceId FROM invoices);" 2>/dev/null || echo 0)
    ORPHAN_CUSTOMERS_REP=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM customers WHERE SupportRepId NOT IN (SELECT EmployeeId FROM employees);" 2>/dev/null || echo 0)
    ORPHAN_ITEMS_TRACK=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM invoice_items WHERE TrackId NOT IN (SELECT TrackId FROM tracks);" 2>/dev/null || echo 0)
    ORPHAN_TRACKS_ALBUM=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM tracks WHERE AlbumId NOT IN (SELECT AlbumId FROM albums);" 2>/dev/null || echo 0)
    ORPHAN_ALBUMS_ARTIST=$(sqlite3 "$TARGET_DB" "SELECT COUNT(*) FROM albums WHERE ArtistId NOT IN (SELECT ArtistId FROM artists);" 2>/dev/null || echo 0)
    
    RI_ERRORS="{ 
        \"orphan_invoices\": $ORPHAN_INVOICES,
        \"orphan_items\": $ORPHAN_ITEMS,
        \"orphan_customers_rep\": $ORPHAN_CUSTOMERS_REP,
        \"orphan_items_track\": $ORPHAN_ITEMS_TRACK,
        \"orphan_tracks_album\": $ORPHAN_TRACKS_ALBUM,
        \"orphan_albums_artist\": $ORPHAN_ALBUMS_ARTIST
    }"
fi

# 4. Compute Ground Truth from Source DB
# We calculate what the counts SHOULD be for a Brazil subset
GROUND_TRUTH="{}"
if [ -f "$SOURCE_DB" ]; then
    # Calculate expected counts based on Brazil customers
    # This logic mimics the requirement to verify correctness
    
    # Expected Customers
    GT_CUSTOMERS=$(sqlite3 "$SOURCE_DB" "SELECT COUNT(*) FROM customers WHERE Country='Brazil';")
    
    # Expected Invoices
    GT_INVOICES=$(sqlite3 "$SOURCE_DB" "SELECT COUNT(*) FROM invoices WHERE CustomerId IN (SELECT CustomerId FROM customers WHERE Country='Brazil');")
    
    # Expected Invoice Items
    GT_ITEMS=$(sqlite3 "$SOURCE_DB" "SELECT COUNT(*) FROM invoice_items WHERE InvoiceId IN (SELECT InvoiceId FROM invoices WHERE CustomerId IN (SELECT CustomerId FROM customers WHERE Country='Brazil'));")
    
    # Expected Tracks (referenced by items)
    GT_TRACKS=$(sqlite3 "$SOURCE_DB" "
        SELECT COUNT(DISTINCT TrackId) FROM invoice_items 
        WHERE InvoiceId IN (SELECT InvoiceId FROM invoices WHERE CustomerId IN (SELECT CustomerId FROM customers WHERE Country='Brazil'));
    ")
    
    # Expected Albums (referenced by tracks) - This requires a deeper nested query or tmp table
    # Using a slightly simplified check for the export script to avoid complex nested SQL string escaping
    # We will trust the verifier to do strict comparison if we just provide the target counts, 
    # but providing at least the root counts is helpful.
    
    GROUND_TRUTH="{ 
        \"customers\": $GT_CUSTOMERS, 
        \"invoices\": $GT_INVOICES, 
        \"invoice_items\": $GT_ITEMS, 
        \"tracks\": $GT_TRACKS 
    }"
fi

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "db_exists": $DB_EXISTS,
    "db_size": $DB_SIZE,
    "script_exists": $SCRIPT_EXISTS,
    "script_size": $SCRIPT_SIZE,
    "connection_exists": $CONNECTION_EXISTS,
    "all_tables_exist": $TABLE_CHECK,
    "target_counts": $TARGET_COUNTS,
    "correct_customers": $CORRECT_CUSTOMERS,
    "ri_errors": $RI_ERRORS,
    "ground_truth": $GROUND_TRUTH,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Export completed. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="