#!/bin/bash
# Export results for backup_database task
echo "=== Exporting task result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Check if SQL Server is running
MSSQL_RUNNING="false"
if mssql_is_running; then
    MSSQL_RUNNING="true"
fi

# Check if Azure Data Studio is running
ADS_RUNNING="false"
if ads_is_running; then
    ADS_RUNNING="true"
fi

# Check if backup file exists
BACKUP_PATH="/backup/AdventureWorks2022_backup.bak"
BACKUP_EXISTS="false"
BACKUP_SIZE_MB=0
BACKUP_VALID="false"
BACKUP_CREATED_RECENTLY="false"

if [ "$MSSQL_RUNNING" = "true" ]; then
    # Check if backup file exists in container
    if docker exec mssql-server test -f "$BACKUP_PATH" 2>/dev/null; then
        BACKUP_EXISTS="true"

        # Get backup file size
        BACKUP_SIZE_BYTES=$(docker exec mssql-server stat -c %s "$BACKUP_PATH" 2>/dev/null || echo "0")
        BACKUP_SIZE_MB=$((BACKUP_SIZE_BYTES / 1024 / 1024))

        # Check if backup was created in the last 30 minutes
        BACKUP_AGE=$(docker exec mssql-server stat -c %Y "$BACKUP_PATH" 2>/dev/null || echo "0")
        CURRENT_TIME=$(date +%s)
        AGE_SECONDS=$((CURRENT_TIME - BACKUP_AGE))
        if [ "$AGE_SECONDS" -lt 1800 ]; then
            BACKUP_CREATED_RECENTLY="true"
        fi

        # Verify backup is valid using RESTORE VERIFYONLY
        VERIFY_RESULT=$(mssql_query_raw "RESTORE VERIFYONLY FROM DISK = '$BACKUP_PATH'" 2>&1)
        QUERY_EXIT_CODE=$?  # Store exit code IMMEDIATELY after query

        if echo "$VERIFY_RESULT" | grep -qi "verified successfully\|is valid"; then
            BACKUP_VALID="true"
        elif echo "$VERIFY_RESULT" | grep -qi "error\|failed"; then
            BACKUP_VALID="false"
        else
            # If no clear success or error, check if the query command completed without error
            if [ $QUERY_EXIT_CODE -eq 0 ]; then
                BACKUP_VALID="true"
            fi
        fi
    fi

    # Check backup history in SQL Server
    BACKUP_HISTORY=$(mssql_query "
        SELECT TOP 1
            backup_start_date,
            backup_finish_date,
            backup_size / 1024 / 1024 AS SizeMB
        FROM msdb.dbo.backupset
        WHERE database_name = 'AdventureWorks2022'
        ORDER BY backup_start_date DESC
    " 2>/dev/null | head -5)
fi

# Check if size is reasonable (at least 100MB for AdventureWorks)
REASONABLE_SIZE="false"
if [ "$BACKUP_SIZE_MB" -ge 100 ]; then
    REASONABLE_SIZE="true"
fi

# Create JSON result in temp file first
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mssql_running": $MSSQL_RUNNING,
    "ads_running": $ADS_RUNNING,
    "backup_exists": $BACKUP_EXISTS,
    "backup_size_mb": $BACKUP_SIZE_MB,
    "backup_valid": $BACKUP_VALID,
    "backup_created_recently": $BACKUP_CREATED_RECENTLY,
    "reasonable_size": $REASONABLE_SIZE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/backup_result.json 2>/dev/null || sudo rm -f /tmp/backup_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/backup_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/backup_result.json
chmod 666 /tmp/backup_result.json 2>/dev/null || sudo chmod 666 /tmp/backup_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/backup_result.json"
cat /tmp/backup_result.json
echo ""

if [ "$BACKUP_EXISTS" = "true" ]; then
    echo "Backup file details:"
    docker exec mssql-server ls -lh "$BACKUP_PATH" 2>/dev/null
    echo ""
    echo "Backup history:"
    echo "$BACKUP_HISTORY"
fi

echo ""
echo "=== Export complete ==="
