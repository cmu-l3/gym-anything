#!/bin/bash
set -e
echo "=== Setting up multi_database_health_census task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
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

# Verify all 4 databases exist and capture Ground Truth
GROUND_TRUTH_DIR="/tmp/census_ground_truth"
mkdir -p "$GROUND_TRUTH_DIR"
chmod 700 "$GROUND_TRUTH_DIR"

echo "Capturing ground truth..."

# 1. Table Counts per DB
for db in DrTuxTest MedicaTuxTest CIM10Test CCAMTest; do
    mysql -u root -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db'" 2>/dev/null > "$GROUND_TRUTH_DIR/${db}_table_count.txt"
done

# 2. Row counts for all tables (for verification)
mysql -u root -N -e "SELECT table_schema, table_name, table_rows FROM information_schema.tables WHERE table_schema IN ('DrTuxTest','MedicaTuxTest','CIM10Test','CCAMTest')" 2>/dev/null > "$GROUND_TRUTH_DIR/all_table_rows.txt"

# 3. Patient Count (IndexNomPrenom is the search index, fchpat is the file)
# We use IndexNomPrenom with Type='Dossier' as the definitive count of patient files
mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'" 2>/dev/null > "$GROUND_TRUTH_DIR/patient_count.txt"

# 4. Top 5 Largest Tables
mysql -u root -N -e "
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema IN ('DrTuxTest','MedicaTuxTest','CIM10Test','CCAMTest') 
ORDER BY table_rows DESC 
LIMIT 5" 2>/dev/null > "$GROUND_TRUTH_DIR/top_5_tables.txt"

# 5. fchpat Schema
mysql -u root -N -e "
SELECT column_name 
FROM information_schema.columns 
WHERE table_schema='DrTuxTest' AND table_name='fchpat'" 2>/dev/null > "$GROUND_TRUTH_DIR/fchpat_columns.txt"

# 6. CIM10 and CCAM rough counts (using largest table in each schema as proxy for code count)
mysql -u root -N -e "SELECT MAX(table_rows) FROM information_schema.tables WHERE table_schema='CIM10Test'" 2>/dev/null > "$GROUND_TRUTH_DIR/cim10_count.txt"
mysql -u root -N -e "SELECT MAX(table_rows) FROM information_schema.tables WHERE table_schema='CCAMTest'" 2>/dev/null > "$GROUND_TRUTH_DIR/ccam_count.txt"

# Ensure output directory exists for agent
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
rm -f /home/ga/Documents/medintux_data_census.txt

# Launch MedinTux Manager for visual context (even though task is data-heavy)
launch_medintux_manager || echo "WARNING: MedinTux Manager failed to start"

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="