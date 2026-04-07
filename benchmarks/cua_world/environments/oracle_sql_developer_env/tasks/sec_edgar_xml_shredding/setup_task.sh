#!/bin/bash
echo "=== Setting up SEC EDGAR XML Shredding Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time and initial state
date +%s > /home/ga/.task_start_time
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents/exports

# Verify Oracle container is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

# Clean up previous run artifacts
echo "Cleaning up any previous schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER edgar_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# Create EDGAR_ADMIN user
echo "Creating EDGAR_ADMIN schema..."
oracle_query "CREATE USER edgar_admin IDENTIFIED BY Edgar2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO edgar_admin;
GRANT RESOURCE TO edgar_admin;
GRANT CREATE VIEW TO edgar_admin;
GRANT CREATE SESSION TO edgar_admin;
GRANT CREATE TABLE TO edgar_admin;
EXIT;" "system"

# Create tables and populate with simulated SEC XML data
echo "Populating SEC XML Data and Stock Prices..."
sudo docker exec -i oracle-xe sqlplus -s edgar_admin/Edgar2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE RAW_13F_FILINGS (
    accession_number VARCHAR2(50) PRIMARY KEY,
    filer_name VARCHAR2(100),
    filing_date DATE,
    filing_xml XMLTYPE
);

CREATE TABLE QUARTERLY_PRICES (
    cusip VARCHAR2(9) PRIMARY KEY,
    ticker VARCHAR2(10),
    issuer_name VARCHAR2(100),
    closing_price NUMBER
);

-- Insert Q4 2023 End of Quarter Reference Prices
INSERT INTO QUARTERLY_PRICES VALUES ('037833100', 'AAPL', 'APPLE INC', 150.00);
INSERT INTO QUARTERLY_PRICES VALUES ('594918104', 'MSFT', 'MICROSOFT CORP', 350.00);
INSERT INTO QUARTERLY_PRICES VALUES ('023135106', 'AMZN', 'AMAZON COM INC', 120.00);
INSERT INTO QUARTERLY_PRICES VALUES ('88160R101', 'TSLA', 'TESLA INC', 200.00);

-- Filer 1: Berkshire Hathaway (Correctly reported in thousands)
INSERT INTO RAW_13F_FILINGS VALUES ('0001085146-23-000001', 'BERKSHIRE HATHAWAY', TO_DATE('2023-12-31','YYYY-MM-DD'), XMLTYPE(
'<?xml version="1.0"?><informationTable xmlns="http://www.sec.gov/edgar/document/thirteenf/informationtable"><infoTable><nameOfIssuer>APPLE INC</nameOfIssuer><cusip>037833100</cusip><value>1500000</value><shrsOrPrnAmt><sshPrnamt>10000000</sshPrnamt></shrsOrPrnAmt></infoTable><infoTable><nameOfIssuer>AMAZON COM INC</nameOfIssuer><cusip>023135106</cusip><value>120000</value><shrsOrPrnAmt><sshPrnamt>1000000</sshPrnamt></shrsOrPrnAmt></infoTable></informationTable>'
));

-- Filer 2: Renaissance Tech (Scale Error! Values are mistakenly reported in exact dollars)
INSERT INTO RAW_13F_FILINGS VALUES ('0001567619-23-000002', 'RENAISSANCE TECH', TO_DATE('2023-12-31','YYYY-MM-DD'), XMLTYPE(
'<?xml version="1.0"?><informationTable xmlns="http://www.sec.gov/edgar/document/thirteenf/informationtable"><infoTable><nameOfIssuer>APPLE INC</nameOfIssuer><cusip>037833100</cusip><value>75000000</value><shrsOrPrnAmt><sshPrnamt>500000</sshPrnamt></shrsOrPrnAmt></infoTable><infoTable><nameOfIssuer>MICROSOFT CORP</nameOfIssuer><cusip>594918104</cusip><value>70000000</value><shrsOrPrnAmt><sshPrnamt>200000</sshPrnamt></shrsOrPrnAmt></infoTable></informationTable>'
));

-- Filer 3: Blackrock (Mixed bag, TSLA has scale error)
INSERT INTO RAW_13F_FILINGS VALUES ('0001193125-23-000003', 'BLACKROCK INC', TO_DATE('2023-12-31','YYYY-MM-DD'), XMLTYPE(
'<?xml version="1.0"?><informationTable xmlns="http://www.sec.gov/edgar/document/thirteenf/informationtable"><infoTable><nameOfIssuer>APPLE INC</nameOfIssuer><cusip>037833100</cusip><value>300000</value><shrsOrPrnAmt><sshPrnamt>2000000</sshPrnamt></shrsOrPrnAmt></infoTable><infoTable><nameOfIssuer>TESLA INC</nameOfIssuer><cusip>88160R101</cusip><value>10000000</value><shrsOrPrnAmt><sshPrnamt>50000</sshPrnamt></shrsOrPrnAmt></infoTable></informationTable>'
));

COMMIT;
EXIT;
EOSQL
echo "Data populated successfully."

# Pre-configure SQL Developer connection for the agent
ensure_hr_connection "EDGAR Database" "edgar_admin" "Edgar2024"

# Focus and maximize SQL Developer
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Try to double-click open the connection to save the agent time
open_hr_connection_in_sqldeveloper || true

# Take initial screenshot for verification
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="