#!/bin/bash
# Setup script for External Table Cost Analysis task
# Creates CSV files and Oracle Directory object

set -e

echo "=== Setting up External Table Cost Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# --- 1. Verify Oracle is running ---
echo "Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- 2. Create OS Directory for External Data ---
# We create this inside the container volume or mapped path that Oracle can access.
# The oracle-xe image usually has /opt/oracle/oradata or similar.
# We will create a dedicated directory inside the container.

echo "Creating external data directory in container..."
sudo docker exec -u 0 $ORACLE_CONTAINER mkdir -p /opt/oracle/external_data

# --- 3. Generate CSV Files ---

# Create country_cost_indices.csv
cat > /tmp/country_cost_indices.csv << 'CSV'
US,United States,100.0,1.00
CA,Canada,98.2,1.36
UK,United Kingdom,109.4,0.79
DE,Germany,95.8,0.92
JP,Japan,86.3,149.50
IT,Italy,88.7,0.92
CH,Switzerland,130.2,0.88
BR,Brazil,62.4,4.97
CN,China,72.1,7.24
IN,India,38.5,83.12
AU,Australia,107.3,1.53
SG,Singapore,115.8,1.35
MX,Mexico,55.3,17.15
NL,Netherlands,103.5,0.92
IL,Israel,110.2,3.67
AR,Argentina,42.8,850.00
BE,Belgium,101.3,0.92
DK,Denmark,118.7,6.89
EG,Egypt,28.4,30.90
HK,Hong Kong,112.6,7.82
KW,Kuwait,85.4,0.31
NG,Nigeria,31.2,770.00
ZM,Zambia,35.6,25.80
ZW,Zimbabwe,40.1,322.00
KE,Kenya,42.3,153.50
CSV

# Create market_salary_benchmarks.csv
cat > /tmp/market_salary_benchmarks.csv << 'CSV'
AD_PRES,President,185000,232000,295000,380000,2024
AD_VP,Administration Vice President,145000,178000,218000,275000,2024
AD_ASST,Administration Assistant,32000,38500,46000,55000,2024
FI_MGR,Finance Manager,98000,126000,158000,195000,2024
FI_ACCOUNT,Accountant,52000,65000,82000,98000,2024
AC_MGR,Accounting Manager,95000,118000,148000,182000,2024
AC_ACCOUNT,Public Accountant,50000,62000,78000,95000,2024
SA_MAN,Sales Manager,88000,112000,145000,185000,2024
SA_REP,Sales Representative,45000,58000,75000,95000,2024
PU_MAN,Purchasing Manager,82000,105000,132000,165000,2024
PU_CLERK,Purchasing Clerk,28000,34000,42000,52000,2024
ST_MAN,Stock Manager,65000,82000,102000,128000,2024
ST_CLERK,Stock Clerk,26000,32000,40000,48000,2024
SH_CLERK,Shipping Clerk,27000,33000,41000,50000,2024
IT_PROG,Programmer,62000,78000,98000,125000,2024
MK_MAN,Marketing Manager,92000,118000,152000,190000,2024
MK_REP,Marketing Representative,42000,55000,72000,88000,2024
HR_REP,Human Resources Representative,45000,56000,70000,85000,2024
PR_REP,Public Relations Representative,40000,52000,68000,82000,2024
CSV

# Copy files to container and set permissions
sudo docker cp /tmp/country_cost_indices.csv $ORACLE_CONTAINER:/opt/oracle/external_data/
sudo docker cp /tmp/market_salary_benchmarks.csv $ORACLE_CONTAINER:/opt/oracle/external_data/

# Ensure oracle user owns the files (UID 54321 is common for oracle images, or use user name)
sudo docker exec -u 0 $ORACLE_CONTAINER chown -R 54321:54321 /opt/oracle/external_data
sudo docker exec -u 0 $ORACLE_CONTAINER chmod -R 755 /opt/oracle/external_data

# --- 4. Configure Oracle Database ---
# Create Directory Object and clean up old objects

echo "Configuring Oracle DIRECTORY and cleaning schema..."
oracle_query "
-- Connect as SYSTEM to create directory
CONNECT system/${SYSTEM_PWD}@localhost:1521/XEPDB1

CREATE OR REPLACE DIRECTORY EXT_DATA_DIR AS '/opt/oracle/external_data';
GRANT READ, WRITE ON DIRECTORY EXT_DATA_DIR TO hr;

-- Connect as HR to clean up
CONNECT hr/${HR_PWD}@localhost:1521/XEPDB1

-- Drop existing objects if they exist
BEGIN
    EXECUTE IMMEDIATE 'DROP VIEW employee_cost_analysis';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE ext_country_costs';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE ext_market_salaries';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
" "system" > /dev/null 2>&1

# --- 5. Initial State Recording ---
# Count current tables in HR schema (should be standard count)
INITIAL_TABLE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_tables;" "hr" | tr -d ' ')
echo "$INITIAL_TABLE_COUNT" > /tmp/initial_table_count.txt

# Clean up output file if it exists
rm -f /home/ga/Desktop/cost_analysis_report.txt

# Take setup screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Files placed in: /opt/oracle/external_data"
echo "Directory Object: EXT_DATA_DIR"