#!/bin/bash
echo "=== Setting up Hotel Revenue Cancellation Analytics Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# 1. Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi

# 2. Clean up previous runs
echo "Cleaning up schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER revenue_analyst CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# 3. Create Schema and User
echo "Creating REVENUE_ANALYST user..."
oracle_query "CREATE USER revenue_analyst IDENTIFIED BY RevMgmt2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO revenue_analyst;
GRANT RESOURCE TO revenue_analyst;
GRANT CREATE VIEW TO revenue_analyst;
GRANT CREATE PROCEDURE TO revenue_analyst;
GRANT CREATE SESSION TO revenue_analyst;
GRANT CREATE TABLE TO revenue_analyst;
EXIT;" "system"

# 4. Create Tables
echo "Creating tables..."
sudo docker exec -i oracle-xe sqlplus -s revenue_analyst/RevMgmt2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON
CREATE TABLE hotel_bookings (
    booking_id NUMBER PRIMARY KEY,
    hotel VARCHAR2(50),
    is_canceled NUMBER(1),
    lead_time NUMBER,
    arrival_date_year NUMBER,
    arrival_date_month VARCHAR2(20),
    stays_in_weekend_nights NUMBER,
    stays_in_week_nights NUMBER,
    adults NUMBER,
    children NUMBER,
    babies NUMBER,
    market_segment VARCHAR2(50),
    deposit_type VARCHAR2(50),
    reserved_room_type VARCHAR2(10),
    adr NUMBER(10,2)
);
EXIT;
EOSQL

# 5. Load Real Data (Antonio et al. Hotel Booking Dataset)
echo "Downloading real hotel booking dataset..."
python3 - << 'PYEOF'
import csv
import urllib.request
import os

url = "https://raw.githubusercontent.com/rfordatascience/tidytuesday/master/data/2020/2020-02-11/hotels.csv"
try:
    urllib.request.urlretrieve(url, "/tmp/hotels.csv")
    
    with open('/tmp/hotels.csv', 'r') as f:
        reader = csv.DictReader(f)
        out = open('/tmp/load_hotels.sql', 'w')
        out.write('SET DEFINE OFF;\n')
        
        count = 0
        inserted = 0
        for row in reader:
            count += 1
            if count % 10 != 0: continue # Sample 10% to keep load times reasonable (~11k rows)
            
            inserted += 1
            if inserted > 12000: break
            
            hotel = row['hotel'].replace("'", "''")
            is_canceled = row['is_canceled']
            lead_time = row['lead_time']
            arr_year = row['arrival_date_year']
            arr_month = row['arrival_date_month']
            stays_we = row['stays_in_weekend_nights']
            stays_w = row['stays_in_week_nights']
            adults = row['adults']
            children = row.get('children', '0')
            if children == 'NA' or not children: children = '0'
            babies = row['babies']
            market = row['market_segment'].replace("'", "''")
            deposit = row['deposit_type'].replace("'", "''")
            room = row['reserved_room_type'].replace("'", "''")
            adr = row['adr']
            
            out.write(f"INSERT INTO hotel_bookings VALUES ({inserted}, '{hotel}', {is_canceled}, {lead_time}, {arr_year}, '{arr_month}', {stays_we}, {stays_w}, {adults}, {children}, {babies}, '{market}', '{deposit}', '{room}', {adr});\n")
            
        # Inject guaranteed targeted errors for the cleaning task
        out.write(f"INSERT INTO hotel_bookings VALUES (99998, 'City Hotel', 0, 10, 2023, 'July', 1, 2, 0, 0, 0, 'Online TA', 'No Deposit', 'A', 100.00);\n")
        out.write(f"INSERT INTO hotel_bookings VALUES (99999, 'Resort Hotel', 0, 10, 2023, 'July', 1, 2, 2, 0, 0, 'Online TA', 'No Deposit', 'A', -50.00);\n")
        
        out.write('COMMIT;\nEXIT;\n')
        out.close()
        print(f"Generated SQL for {inserted + 2} rows.")
except Exception as e:
    print(f"Error generating data: {e}")
PYEOF

echo "Loading data into database (this may take 30 seconds)..."
sudo docker exec -i oracle-xe sqlplus -s revenue_analyst/RevMgmt2024@//localhost:1521/XEPDB1 < /tmp/load_hotels.sql > /dev/null

# Clean up temp files
rm -f /tmp/hotels.csv /tmp/load_hotels.sql

# Create exports directory
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports
rm -f /home/ga/Documents/exports/lost_revenue.csv

# Configure and open SQL Developer
echo "Configuring SQL Developer..."
ensure_hr_connection "Revenue Database" "revenue_analyst" "RevMgmt2024"

echo "Waiting for SQL Developer to be ready..."
open_hr_connection_in_sqldeveloper

# Record Initial count of invalid records
INVALID_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM hotel_bookings WHERE (adults+children+babies)=0 OR adr<0;" "revenue_analyst" "RevMgmt2024" | tr -d '[:space:]')
echo "$INVALID_COUNT" > /tmp/initial_invalid_count

take_screenshot /tmp/task_initial.png ga

echo "=== Setup Complete ==="