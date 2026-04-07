#!/bin/bash
set -e
echo "=== Setting up CCAM procedure report task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure MySQL is running
echo "Checking MySQL..."
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Wait for MySQL
for i in $(seq 1 15); do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "MySQL ready"
        break
    fi
    sleep 2
done

# Verify CCAMTest database exists and has data
CCAM_TABLES=$(mysql -u root CCAMTest -N -e "SHOW TABLES" 2>/dev/null | wc -l)
echo "CCAMTest tables: $CCAM_TABLES"

if [ "$CCAM_TABLES" -eq 0 ]; then
    echo "WARNING: CCAMTest database is empty. Attempting to reload..."
    # Try to find the SQL dump in standard locations or installer cache
    SQL_DUMP=$(find /opt/medintux -name "Dump_CCAMTest.sql" 2>/dev/null | head -1)
    if [ -z "$SQL_DUMP" ]; then
        SQL_DUMP=$(find /home/ga/.wine/drive_c -name "Dump_CCAMTest.sql" 2>/dev/null | head -1)
    fi
    
    if [ -n "$SQL_DUMP" ]; then
        echo "Reloading from $SQL_DUMP"
        mysql -u root CCAMTest < "$SQL_DUMP" 2>/dev/null || true
        CCAM_TABLES=$(mysql -u root CCAMTest -N -e "SHOW TABLES" 2>/dev/null | wc -l)
        echo "CCAMTest tables after reload: $CCAM_TABLES"
    else
        echo "ERROR: No CCAMTest SQL dump found. Creating dummy data for task continuity."
        mysql -u root CCAMTest -e "CREATE TABLE IF NOT EXISTS CCAM_ACTES (Code VARCHAR(20), Description TEXT, Tarif FLOAT);"
        mysql -u root CCAMTest -e "INSERT INTO CCAM_ACTES VALUES ('AAFA001', 'Exemple acte 1', 25.0), ('AAFA002', 'Exemple acte 2', 30.0);"
    fi
fi

# ============================================================
# Generate Ground Truth (Hidden from Agent)
# ============================================================
echo "Generating ground truth..."
mkdir -p /tmp/ground_truth
chmod 700 /tmp/ground_truth

# 1. Table count
mysql -u root CCAMTest -N -e "SHOW TABLES" 2>/dev/null > /tmp/ground_truth/tables.txt
TABLE_COUNT=$(wc -l < /tmp/ground_truth/tables.txt)
echo "$TABLE_COUNT" > /tmp/ground_truth/table_count.txt

# 2. Find main table and total codes
# We look for the table with the most rows, likely the codes table
MAIN_TABLE=""
MAX_ROWS=0
while IFS= read -r tbl; do
    ROW_COUNT=$(mysql -u root CCAMTest -N -e "SELECT COUNT(*) FROM \`$tbl\`" 2>/dev/null || echo 0)
    echo "$tbl:$ROW_COUNT" >> /tmp/ground_truth/table_rows.txt
    if [ "$ROW_COUNT" -gt "$MAX_ROWS" ]; then
        MAX_ROWS=$ROW_COUNT
        MAIN_TABLE="$tbl"
    fi
done < /tmp/ground_truth/tables.txt

echo "$MAIN_TABLE" > /tmp/ground_truth/main_table.txt
echo "$MAX_ROWS" > /tmp/ground_truth/total_codes.txt

# 3. Get first 20 codes alphabetically for sample verification
# We attempt to find the code and description columns dynamically
COLUMNS=$(mysql -u root CCAMTest -N -e "SHOW COLUMNS FROM \`$MAIN_TABLE\`" 2>/dev/null | awk '{print $1}')
COL1=$(echo "$COLUMNS" | head -1) # Likely Code
COL2=$(echo "$COLUMNS" | head -2 | tail -1) # Likely Description or similar

mysql -u root CCAMTest -N -e "SELECT $COL1, $COL2 FROM \`$MAIN_TABLE\` ORDER BY $COL1 ASC LIMIT 20" 2>/dev/null > /tmp/ground_truth/sample_20.txt || true

# Clean any previous output files
rm -f /home/ga/ccam_report.txt
rm -f /home/ga/ccam_schema.txt

# Ensure MedinTux Manager is running (provides context)
launch_medintux_manager

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== CCAM procedure report task setup complete ==="