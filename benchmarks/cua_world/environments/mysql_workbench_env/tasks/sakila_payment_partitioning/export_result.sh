#!/bin/bash
# Export script for sakila_payment_partitioning task

echo "=== Exporting Sakila Payment Partitioning Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_PAYMENT_COUNT=$(cat /tmp/initial_payment_count 2>/dev/null || echo "0")

# Database Credentials
DB_USER="root"
DB_PASS="GymAnything#2024"
DB_NAME="sakila"

# 1. Check Table Existence
TABLE_EXISTS=$(mysql -u $DB_USER -p$DB_PASS information_schema -N -e "
    SELECT COUNT(*) FROM TABLES 
    WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='payment_archive';
" 2>/dev/null || echo "0")

# 2. Check Partition Method
# Returns 'RANGE' or 'RANGE COLUMNS' if correct
PARTITION_METHOD=$(mysql -u $DB_USER -p$DB_PASS information_schema -N -e "
    SELECT DISTINCT PARTITION_METHOD 
    FROM PARTITIONS 
    WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='payment_archive' 
    AND PARTITION_METHOD IS NOT NULL;
" 2>/dev/null || echo "")

# 3. Check Partition Names
# We expect p2005, p2006, p_future (case insensitive check done in verifier)
PARTITION_NAMES=$(mysql -u $DB_USER -p$DB_PASS information_schema -N -e "
    SELECT GROUP_CONCAT(PARTITION_NAME) 
    FROM PARTITIONS 
    WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='payment_archive';
" 2>/dev/null || echo "")

# 4. Check Data Migration (Row Count)
ARCHIVE_ROW_COUNT=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -e "
    SELECT COUNT(*) FROM payment_archive;
" 2>/dev/null || echo "0")

# 5. Check Data Distribution
# We want to ensure data isn't just dumped into one partition.
# Get row count per partition
PARTITION_DISTRIBUTION=$(mysql -u $DB_USER -p$DB_PASS information_schema -N -e "
    SELECT GROUP_CONCAT(TABLE_ROWS) 
    FROM PARTITIONS 
    WHERE TABLE_SCHEMA='$DB_NAME' AND TABLE_NAME='payment_archive'
    ORDER BY PARTITION_NAME;
" 2>/dev/null || echo "")

# 6. Check Stored Procedure Existence
PROC_EXISTS=$(mysql -u $DB_USER -p$DB_PASS information_schema -N -e "
    SELECT COUNT(*) FROM ROUTINES 
    WHERE ROUTINE_SCHEMA='$DB_NAME' AND ROUTINE_NAME='sp_partition_stats';
" 2>/dev/null || echo "0")

# 7. Check CSV Export
CSV_FILE="/home/ga/Documents/exports/partition_stats.csv"
CSV_EXISTS="false"
CSV_MTIME=0
CSV_SIZE=0
CSV_CONTENT_VALID="false"

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$CSV_FILE" 2>/dev/null || echo "0")
    CSV_SIZE=$(stat -c%s "$CSV_FILE" 2>/dev/null || echo "0")
    
    # Check if CSV contains partition names
    if grep -qi "p2005" "$CSV_FILE" || grep -qi "p2006" "$CSV_FILE"; then
        CSV_CONTENT_VALID="true"
    fi
fi

# Package result into JSON
cat > /tmp/partitioning_result.json << EOF
{
    "table_exists": $TABLE_EXISTS,
    "partition_method": "$PARTITION_METHOD",
    "partition_names": "$PARTITION_NAMES",
    "archive_row_count": $ARCHIVE_ROW_COUNT,
    "initial_payment_count": $INITIAL_PAYMENT_COUNT,
    "partition_distribution": "$PARTITION_DISTRIBUTION",
    "proc_exists": $PROC_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_mtime": $CSV_MTIME,
    "csv_size": $CSV_SIZE,
    "csv_content_valid": $CSV_CONTENT_VALID,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Export completed. JSON generated at /tmp/partitioning_result.json"
cat /tmp/partitioning_result.json