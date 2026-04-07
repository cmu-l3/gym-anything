#!/bin/bash
# Setup script for Fiscal Period Close Reconciliation task
echo "=== Setting up Fiscal Period Close Reconciliation ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# ---------------------------------------------------------------
# 1. Verify Oracle is running and HR schema is accessible
# ---------------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

HR_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM hr.employees;" "system" | tr -d '[:space:]')
if [ -z "$HR_CHECK" ] || [ "$HR_CHECK" = "ERROR" ] || [ "$HR_CHECK" -lt 1 ] 2>/dev/null; then
    echo "ERROR: HR schema not loaded or inaccessible"
    exit 1
fi
echo "HR schema verified ($HR_CHECK employees)"

# ---------------------------------------------------------------
# 2. Clean up previous run artifacts (idempotent re-runs)
# ---------------------------------------------------------------
echo "Cleaning up previous run artifacts..."

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER fiscal_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# ---------------------------------------------------------------
# 3. Create FISCAL schema with fiscal_admin user
# ---------------------------------------------------------------
echo "Creating FISCAL schema (fiscal_admin user)..."

oracle_query "CREATE USER fiscal_admin IDENTIFIED BY Fiscal2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO fiscal_admin;
GRANT RESOURCE TO fiscal_admin;
GRANT CREATE MATERIALIZED VIEW TO fiscal_admin;
GRANT CREATE VIEW TO fiscal_admin;
GRANT CREATE PROCEDURE TO fiscal_admin;
GRANT CREATE SESSION TO fiscal_admin;
GRANT CREATE SEQUENCE TO fiscal_admin;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create fiscal_admin user"
    exit 1
fi
echo "fiscal_admin user created with required privileges"

# ---------------------------------------------------------------
# 4. Create tables under FISCAL schema
# ---------------------------------------------------------------
echo "Creating FISCAL schema tables..."

# -- ENTITIES table (must be created first, referenced by JOURNAL_ENTRIES)
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE entities (
    entity_id    NUMBER        PRIMARY KEY,
    entity_name  VARCHAR2(100) NOT NULL,
    entity_type  VARCHAR2(20)  NOT NULL
);

EXIT;
EOSQL
echo "  ENTITIES table created"

# -- CHART_OF_ACCOUNTS table
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE chart_of_accounts (
    account_id       NUMBER        PRIMARY KEY,
    account_number   VARCHAR2(20)  NOT NULL,
    account_name     VARCHAR2(100) NOT NULL,
    account_category VARCHAR2(20)  NOT NULL
        CONSTRAINT chk_acct_category CHECK (account_category IN ('Assets','Liabilities','Equity','Revenue','Expenses')),
    account_type     VARCHAR2(50),
    normal_balance   VARCHAR2(6)   NOT NULL
        CONSTRAINT chk_normal_bal CHECK (normal_balance IN ('DEBIT','CREDIT')),
    is_active        NUMBER(1)     DEFAULT 1
);

EXIT;
EOSQL
echo "  CHART_OF_ACCOUNTS table created"

# -- COST_CENTERS table
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE cost_centers (
    center_id    NUMBER        PRIMARY KEY,
    center_code  VARCHAR2(10)  NOT NULL,
    center_name  VARCHAR2(100) NOT NULL,
    entity_id    NUMBER
);

EXIT;
EOSQL
echo "  COST_CENTERS table created"

# -- JOURNAL_ENTRIES table
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE journal_entries (
    entry_id        NUMBER        PRIMARY KEY,
    entry_number    VARCHAR2(20)  UNIQUE NOT NULL,
    entry_date      DATE          NOT NULL,
    description     VARCHAR2(200),
    posted_by       VARCHAR2(50),
    status          VARCHAR2(20)  DEFAULT 'POSTED',
    entity_id       NUMBER        REFERENCES entities(entity_id),
    is_intercompany NUMBER(1)     DEFAULT 0
);

EXIT;
EOSQL
echo "  JOURNAL_ENTRIES table created"

# -- JOURNAL_LINES table
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE journal_lines (
    line_id          NUMBER        PRIMARY KEY,
    entry_id         NUMBER        REFERENCES journal_entries(entry_id),
    account_id       NUMBER        REFERENCES chart_of_accounts(account_id),
    center_id        NUMBER        REFERENCES cost_centers(center_id),
    debit_amount     NUMBER(15,2)  DEFAULT 0,
    credit_amount    NUMBER(15,2)  DEFAULT 0,
    line_description VARCHAR2(200)
);

EXIT;
EOSQL
echo "  JOURNAL_LINES table created"

# -- INTERCOMPANY_ELIMINATIONS table
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE intercompany_eliminations (
    elim_id         NUMBER        PRIMARY KEY,
    source_entry_id NUMBER,
    target_entry_id NUMBER,
    amount          NUMBER(15,2),
    status          VARCHAR2(20)  DEFAULT 'PENDING'
);

EXIT;
EOSQL
echo "  INTERCOMPANY_ELIMINATIONS table created"

# ---------------------------------------------------------------
# 5. Create sequences for IDs
# ---------------------------------------------------------------
echo "Creating sequences..."

sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE SEQUENCE entity_seq       START WITH 100 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE account_seq      START WITH 200 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE center_seq       START WITH 100 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE entry_seq        START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE line_seq         START WITH 5000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE elim_seq         START WITH 100 INCREMENT BY 1 NOCACHE;

EXIT;
EOSQL
echo "  Sequences created"

# ---------------------------------------------------------------
# 6. Insert reference data: Entities, Chart of Accounts, Cost Centers
# ---------------------------------------------------------------
echo "Inserting reference data..."

# -- Entities
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

INSERT INTO entities (entity_id, entity_name, entity_type) VALUES (1, 'Acme Manufacturing Corp', 'PARENT');
INSERT INTO entities (entity_id, entity_name, entity_type) VALUES (2, 'Acme Components LLC', 'SUBSIDIARY');
COMMIT;

EXIT;
EOSQL
echo "  2 entities inserted"

# -- Chart of Accounts (~30 accounts based on manufacturing company structure)
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- ASSETS
INSERT INTO chart_of_accounts VALUES (1, '1000', 'Cash and Cash Equivalents',    'Assets', 'Current Asset',     'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (2, '1100', 'Accounts Receivable',          'Assets', 'Current Asset',     'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (3, '1200', 'Inventory - Raw Materials',    'Assets', 'Current Asset',     'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (4, '1210', 'Inventory - Work in Progress', 'Assets', 'Current Asset',     'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (5, '1220', 'Inventory - Finished Goods',   'Assets', 'Current Asset',     'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (6, '1300', 'Prepaid Expenses',             'Assets', 'Current Asset',     'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (7, '1500', 'Property, Plant & Equipment',  'Assets', 'Fixed Asset',       'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (8, '1510', 'Accumulated Depreciation',     'Assets', 'Contra Asset',      'CREDIT', 1);
INSERT INTO chart_of_accounts VALUES (9, '1600', 'Intangible Assets',            'Assets', 'Fixed Asset',       'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (10,'1700', 'Other Long-term Assets',       'Assets', 'Long-term Asset',   'DEBIT', 1);

-- LIABILITIES
INSERT INTO chart_of_accounts VALUES (11,'2000', 'Accounts Payable',             'Liabilities', 'Current Liability',   'CREDIT', 1);
INSERT INTO chart_of_accounts VALUES (12,'2100', 'Accrued Liabilities',          'Liabilities', 'Current Liability',   'CREDIT', 1);
INSERT INTO chart_of_accounts VALUES (13,'2200', 'Current Portion of LT Debt',   'Liabilities', 'Current Liability',   'CREDIT', 1);
INSERT INTO chart_of_accounts VALUES (14,'2300', 'Accrued Payroll',              'Liabilities', 'Current Liability',   'CREDIT', 1);
INSERT INTO chart_of_accounts VALUES (15,'2500', 'Long-term Debt',               'Liabilities', 'Long-term Liability', 'CREDIT', 1);
INSERT INTO chart_of_accounts VALUES (16,'2600', 'Deferred Revenue',             'Liabilities', 'Current Liability',   'CREDIT', 1);

-- EQUITY
INSERT INTO chart_of_accounts VALUES (17,'3000', 'Common Stock',                 'Equity', 'Equity',            'CREDIT', 1);
INSERT INTO chart_of_accounts VALUES (18,'3100', 'Retained Earnings',            'Equity', 'Equity',            'CREDIT', 1);
INSERT INTO chart_of_accounts VALUES (19,'3200', 'Additional Paid-in Capital',   'Equity', 'Equity',            'CREDIT', 1);

-- REVENUE
INSERT INTO chart_of_accounts VALUES (20,'4000', 'Sales Revenue',                'Revenue', 'Operating Revenue', 'CREDIT', 1);
INSERT INTO chart_of_accounts VALUES (21,'4100', 'Intercompany Revenue',         'Revenue', 'Intercompany',      'CREDIT', 1);
INSERT INTO chart_of_accounts VALUES (22,'4200', 'Other Income',                 'Revenue', 'Non-operating',     'CREDIT', 1);

-- EXPENSES
INSERT INTO chart_of_accounts VALUES (23,'5000', 'Cost of Goods Sold',           'Expenses', 'Direct Cost',       'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (24,'5100', 'Direct Labor',                 'Expenses', 'Direct Cost',       'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (25,'5200', 'Manufacturing Overhead',       'Expenses', 'Direct Cost',       'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (26,'6000', 'Salaries and Wages',           'Expenses', 'SGA',               'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (27,'6100', 'Employee Benefits',            'Expenses', 'SGA',               'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (28,'6200', 'Depreciation Expense',         'Expenses', 'SGA',               'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (29,'6300', 'Utilities Expense',            'Expenses', 'Operating',         'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (30,'6400', 'Interest Expense',             'Expenses', 'Non-operating',     'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (31,'6500', 'Sales and Marketing',          'Expenses', 'SGA',               'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (32,'6600', 'Office and Admin Expenses',    'Expenses', 'SGA',               'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (33,'6700', 'Insurance Expense',            'Expenses', 'Operating',         'DEBIT', 1);
INSERT INTO chart_of_accounts VALUES (34,'6800', 'Intercompany COGS',            'Expenses', 'Intercompany',      'DEBIT', 1);

COMMIT;

EXIT;
EOSQL
echo "  34 chart of accounts entries inserted"

# -- Cost Centers
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

INSERT INTO cost_centers VALUES (1, 'CC-HQ',   'Corporate HQ',          1);
INSERT INTO cost_centers VALUES (2, 'CC-PLANT', 'Plant Operations',      1);
INSERT INTO cost_centers VALUES (3, 'CC-SALES', 'Sales & Distribution',  1);
COMMIT;

EXIT;
EOSQL
echo "  3 cost centers inserted"

# ---------------------------------------------------------------
# 7. Insert journal entries - normal Q3 2024 transactions
#    Based on US Census ASM ratios for mid-size manufacturer:
#    Revenue ~$10M/quarter, COGS ~65%, SGA ~20%, Net margin ~8%
# ---------------------------------------------------------------
echo "Inserting journal entries (Q3 2024)..."

# -- Batch 1: Sales Revenue entries (entries 1-8)
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- JE-2024-0001: July Sales Revenue - Week 1
INSERT INTO journal_entries VALUES (1, 'JE-2024-0001', DATE '2024-07-05', 'Weekly sales revenue batch - Week 1 July', 'M.Chen', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (1, 1, 2, 3, 850000.00, 0, 'AR from product sales W1 Jul');
INSERT INTO journal_lines VALUES (2, 1, 20, 3, 0, 850000.00, 'Sales revenue W1 Jul');

-- JE-2024-0002: July Sales Revenue - Week 2
INSERT INTO journal_entries VALUES (2, 'JE-2024-0002', DATE '2024-07-12', 'Weekly sales revenue batch - Week 2 July', 'M.Chen', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (3, 2, 2, 3, 920000.00, 0, 'AR from product sales W2 Jul');
INSERT INTO journal_lines VALUES (4, 2, 20, 3, 0, 920000.00, 'Sales revenue W2 Jul');

-- JE-2024-0003: July Sales Revenue - Week 3
INSERT INTO journal_entries VALUES (3, 'JE-2024-0003', DATE '2024-07-19', 'Weekly sales revenue batch - Week 3 July', 'M.Chen', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (5, 3, 2, 3, 780000.00, 0, 'AR from product sales W3 Jul');
INSERT INTO journal_lines VALUES (6, 3, 20, 3, 0, 780000.00, 'Sales revenue W3 Jul');

-- JE-2024-0004: July Sales Revenue - Week 4
INSERT INTO journal_entries VALUES (4, 'JE-2024-0004', DATE '2024-07-26', 'Weekly sales revenue batch - Week 4 July', 'M.Chen', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (7, 4, 2, 3, 950000.00, 0, 'AR from product sales W4 Jul');
INSERT INTO journal_lines VALUES (8, 4, 20, 3, 0, 950000.00, 'Sales revenue W4 Jul');

-- JE-2024-0005: August Sales Revenue - Week 1
INSERT INTO journal_entries VALUES (5, 'JE-2024-0005', DATE '2024-08-02', 'Weekly sales revenue batch - Week 1 Aug', 'M.Chen', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (9, 5, 2, 3, 870000.00, 0, 'AR from product sales W1 Aug');
INSERT INTO journal_lines VALUES (10, 5, 20, 3, 0, 870000.00, 'Sales revenue W1 Aug');

-- JE-2024-0006: August Sales Revenue - Week 2
INSERT INTO journal_entries VALUES (6, 'JE-2024-0006', DATE '2024-08-09', 'Weekly sales revenue batch - Week 2 Aug', 'M.Chen', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (11, 6, 2, 3, 910000.00, 0, 'AR from product sales W2 Aug');
INSERT INTO journal_lines VALUES (12, 6, 20, 3, 0, 910000.00, 'Sales revenue W2 Aug');

-- JE-2024-0007: August Sales Revenue - Week 3
INSERT INTO journal_entries VALUES (7, 'JE-2024-0007', DATE '2024-08-16', 'Weekly sales revenue batch - Week 3 Aug', 'M.Chen', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (13, 7, 2, 3, 830000.00, 0, 'AR from product sales W3 Aug');
INSERT INTO journal_lines VALUES (14, 7, 20, 3, 0, 830000.00, 'Sales revenue W3 Aug');

-- JE-2024-0008: August Sales Revenue - Week 4
INSERT INTO journal_entries VALUES (8, 'JE-2024-0008', DATE '2024-08-23', 'Weekly sales revenue batch - Week 4 Aug', 'M.Chen', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (15, 8, 2, 3, 890000.00, 0, 'AR from product sales W4 Aug');
INSERT INTO journal_lines VALUES (16, 8, 20, 3, 0, 890000.00, 'Sales revenue W4 Aug');

COMMIT;

EXIT;
EOSQL

# -- Batch 2: More sales, COGS entries (entries 9-18)
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- JE-2024-0009: September Sales Revenue - Week 1
INSERT INTO journal_entries VALUES (9, 'JE-2024-0009', DATE '2024-09-06', 'Weekly sales revenue batch - Week 1 Sep', 'M.Chen', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (17, 9, 2, 3, 960000.00, 0, 'AR from product sales W1 Sep');
INSERT INTO journal_lines VALUES (18, 9, 20, 3, 0, 960000.00, 'Sales revenue W1 Sep');

-- JE-2024-0010: September Sales Revenue - Week 2
INSERT INTO journal_entries VALUES (10, 'JE-2024-0010', DATE '2024-09-13', 'Weekly sales revenue batch - Week 2 Sep', 'M.Chen', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (19, 10, 2, 3, 1040000.00, 0, 'AR from product sales W2 Sep');
INSERT INTO journal_lines VALUES (20, 10, 20, 3, 0, 1040000.00, 'Sales revenue W2 Sep');

-- JE-2024-0011: July COGS batch
INSERT INTO journal_entries VALUES (11, 'JE-2024-0011', DATE '2024-07-31', 'Monthly COGS - July 2024', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (21, 11, 23, 2, 2275000.00, 0, 'COGS July (65% of $3.5M revenue)');
INSERT INTO journal_lines VALUES (22, 11, 5, 2, 0, 2275000.00, 'Finished goods consumed July');

-- JE-2024-0012: August COGS batch
INSERT INTO journal_entries VALUES (12, 'JE-2024-0012', DATE '2024-08-31', 'Monthly COGS - August 2024', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (23, 12, 23, 2, 2275500.00, 0, 'COGS August (65% of $3.5M revenue)');
INSERT INTO journal_lines VALUES (24, 12, 5, 2, 0, 2275500.00, 'Finished goods consumed August');

-- JE-2024-0013: September COGS batch
INSERT INTO journal_entries VALUES (13, 'JE-2024-0013', DATE '2024-09-30', 'Monthly COGS - September 2024', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (25, 13, 23, 2, 1300000.00, 0, 'COGS September (65% of $2M revenue)');
INSERT INTO journal_lines VALUES (26, 13, 5, 2, 0, 1300000.00, 'Finished goods consumed September');

-- JE-2024-0014: July Payroll - Plant workers
INSERT INTO journal_entries VALUES (14, 'JE-2024-0014', DATE '2024-07-31', 'July payroll - Plant operations', 'S.Williams', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (27, 14, 24, 2, 185000.00, 0, 'Direct labor July');
INSERT INTO journal_lines VALUES (28, 14, 1, 1, 0, 185000.00, 'Cash disbursement payroll Jul');

-- JE-2024-0015: August Payroll - Plant workers
INSERT INTO journal_entries VALUES (15, 'JE-2024-0015', DATE '2024-08-31', 'August payroll - Plant operations', 'S.Williams', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (29, 15, 24, 2, 185000.00, 0, 'Direct labor August');
INSERT INTO journal_lines VALUES (30, 15, 1, 1, 0, 185000.00, 'Cash disbursement payroll Aug');

-- JE-2024-0016: September Payroll - Plant workers
INSERT INTO journal_entries VALUES (16, 'JE-2024-0016', DATE '2024-09-30', 'September payroll - Plant operations', 'S.Williams', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (31, 16, 24, 2, 190000.00, 0, 'Direct labor September');
INSERT INTO journal_lines VALUES (32, 16, 1, 1, 0, 190000.00, 'Cash disbursement payroll Sep');

-- JE-2024-0017: July SGA Salaries
INSERT INTO journal_entries VALUES (17, 'JE-2024-0017', DATE '2024-07-31', 'July SGA salaries and wages', 'S.Williams', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (33, 17, 26, 1, 225000.00, 0, 'SGA salaries Jul');
INSERT INTO journal_lines VALUES (34, 17, 14, 1, 0, 225000.00, 'Accrued payroll Jul');

-- JE-2024-0018: August SGA Salaries
INSERT INTO journal_entries VALUES (18, 'JE-2024-0018', DATE '2024-08-31', 'August SGA salaries and wages', 'S.Williams', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (35, 18, 26, 1, 225000.00, 0, 'SGA salaries Aug');
INSERT INTO journal_lines VALUES (36, 18, 14, 1, 0, 225000.00, 'Accrued payroll Aug');

COMMIT;

EXIT;
EOSQL

# -- Batch 3: More operational entries (entries 19-30)
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- JE-2024-0019: September SGA Salaries
INSERT INTO journal_entries VALUES (19, 'JE-2024-0019', DATE '2024-09-30', 'September SGA salaries and wages', 'S.Williams', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (37, 19, 26, 1, 230000.00, 0, 'SGA salaries Sep');
INSERT INTO journal_lines VALUES (38, 19, 14, 1, 0, 230000.00, 'Accrued payroll Sep');

-- JE-2024-0020: July Depreciation
INSERT INTO journal_entries VALUES (20, 'JE-2024-0020', DATE '2024-07-31', 'Monthly depreciation - July', 'A.Johnson', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (39, 20, 28, 2, 45000.00, 0, 'Depreciation expense Jul');
INSERT INTO journal_lines VALUES (40, 20, 8, 2, 0, 45000.00, 'Accumulated depreciation Jul');

-- JE-2024-0021: August Depreciation
INSERT INTO journal_entries VALUES (21, 'JE-2024-0021', DATE '2024-08-31', 'Monthly depreciation - August', 'A.Johnson', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (41, 21, 28, 2, 45000.00, 0, 'Depreciation expense Aug');
INSERT INTO journal_lines VALUES (42, 21, 8, 2, 0, 45000.00, 'Accumulated depreciation Aug');

-- JE-2024-0022: September Depreciation
INSERT INTO journal_entries VALUES (22, 'JE-2024-0022', DATE '2024-09-30', 'Monthly depreciation - September', 'A.Johnson', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (43, 22, 28, 2, 45000.00, 0, 'Depreciation expense Sep');
INSERT INTO journal_lines VALUES (44, 22, 8, 2, 0, 45000.00, 'Accumulated depreciation Sep');

-- JE-2024-0023: Sales and Marketing Expense (normal entry - will be duplicated as ERROR 2)
INSERT INTO journal_entries VALUES (23, 'JE-2024-0023', DATE '2024-08-15', 'Trade show booth and marketing materials', 'L.Garcia', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (45, 23, 31, 3, 12500.00, 0, 'Trade show marketing expense');
INSERT INTO journal_lines VALUES (46, 23, 1, 1, 0, 12500.00, 'Cash payment for trade show');

-- JE-2024-0024: July Utilities
INSERT INTO journal_entries VALUES (24, 'JE-2024-0024', DATE '2024-07-31', 'July utility bills - plant and offices', 'K.Brown', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (47, 24, 29, 2, 38500.00, 0, 'Utilities expense Jul');
INSERT INTO journal_lines VALUES (48, 24, 11, 2, 0, 38500.00, 'AP for utilities Jul');

-- JE-2024-0025: August Utilities
INSERT INTO journal_entries VALUES (25, 'JE-2024-0025', DATE '2024-08-31', 'August utility bills - plant and offices', 'K.Brown', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (49, 25, 29, 2, 41200.00, 0, 'Utilities expense Aug');
INSERT INTO journal_lines VALUES (50, 25, 11, 2, 0, 41200.00, 'AP for utilities Aug');

-- JE-2024-0026: September Utilities
INSERT INTO journal_entries VALUES (26, 'JE-2024-0026', DATE '2024-09-30', 'September utility bills - plant and offices', 'K.Brown', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (51, 26, 29, 2, 39800.00, 0, 'Utilities expense Sep');
INSERT INTO journal_lines VALUES (52, 26, 11, 2, 0, 39800.00, 'AP for utilities Sep');

-- JE-2024-0027: July Interest Payment
INSERT INTO journal_entries VALUES (27, 'JE-2024-0027', DATE '2024-07-15', 'Monthly interest on term loan', 'A.Johnson', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (53, 27, 30, 1, 18750.00, 0, 'Interest expense Jul');
INSERT INTO journal_lines VALUES (54, 27, 1, 1, 0, 18750.00, 'Cash payment interest Jul');

-- JE-2024-0028: August Interest Payment
INSERT INTO journal_entries VALUES (28, 'JE-2024-0028', DATE '2024-08-15', 'Monthly interest on term loan', 'A.Johnson', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (55, 28, 30, 1, 18750.00, 0, 'Interest expense Aug');
INSERT INTO journal_lines VALUES (56, 28, 1, 1, 0, 18750.00, 'Cash payment interest Aug');

-- JE-2024-0029: September Interest Payment
INSERT INTO journal_entries VALUES (29, 'JE-2024-0029', DATE '2024-09-15', 'Monthly interest on term loan', 'A.Johnson', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (57, 29, 30, 1, 18750.00, 0, 'Interest expense Sep');
INSERT INTO journal_lines VALUES (58, 29, 1, 1, 0, 18750.00, 'Cash payment interest Sep');

-- JE-2024-0030: Employee Benefits - Q3
INSERT INTO journal_entries VALUES (30, 'JE-2024-0030', DATE '2024-09-30', 'Q3 employee benefits accrual', 'S.Williams', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (59, 30, 27, 1, 142000.00, 0, 'Employee benefits Q3');
INSERT INTO journal_lines VALUES (60, 30, 12, 1, 0, 142000.00, 'Accrued benefits Q3');

COMMIT;

EXIT;
EOSQL

# -- Batch 4: More operational entries (entries 31-42)
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- JE-2024-0031: Cash Collections from AR - July
INSERT INTO journal_entries VALUES (31, 'JE-2024-0031', DATE '2024-07-20', 'Customer payments received - July batch', 'M.Chen', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (61, 31, 1, 1, 3200000.00, 0, 'Cash received from customers Jul');
INSERT INTO journal_lines VALUES (62, 31, 2, 3, 0, 3200000.00, 'AR collections Jul');

-- JE-2024-0032: Cash Collections from AR - August
INSERT INTO journal_entries VALUES (32, 'JE-2024-0032', DATE '2024-08-20', 'Customer payments received - August batch', 'M.Chen', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (63, 32, 1, 1, 3100000.00, 0, 'Cash received from customers Aug');
INSERT INTO journal_lines VALUES (64, 32, 2, 3, 0, 3100000.00, 'AR collections Aug');

-- JE-2024-0033: Cash Collections from AR - September
INSERT INTO journal_entries VALUES (33, 'JE-2024-0033', DATE '2024-09-20', 'Customer payments received - September batch', 'M.Chen', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (65, 33, 1, 1, 1800000.00, 0, 'Cash received from customers Sep');
INSERT INTO journal_lines VALUES (66, 33, 2, 3, 0, 1800000.00, 'AR collections Sep');

-- JE-2024-0034: AP Payments - July
INSERT INTO journal_entries VALUES (34, 'JE-2024-0034', DATE '2024-07-25', 'Vendor payments - July batch', 'K.Brown', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (67, 34, 11, 2, 1850000.00, 0, 'AP payments to vendors Jul');
INSERT INTO journal_lines VALUES (68, 34, 1, 1, 0, 1850000.00, 'Cash disbursement vendors Jul');

-- JE-2024-0035: AP Payments - August
INSERT INTO journal_entries VALUES (35, 'JE-2024-0035', DATE '2024-08-25', 'Vendor payments - August batch', 'K.Brown', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (69, 35, 11, 2, 1900000.00, 0, 'AP payments to vendors Aug');
INSERT INTO journal_lines VALUES (70, 35, 1, 1, 0, 1900000.00, 'Cash disbursement vendors Aug');

-- JE-2024-0036: AP Payments - September
INSERT INTO journal_entries VALUES (36, 'JE-2024-0036', DATE '2024-09-25', 'Vendor payments - September batch', 'K.Brown', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (71, 36, 11, 2, 1200000.00, 0, 'AP payments to vendors Sep');
INSERT INTO journal_lines VALUES (72, 36, 1, 1, 0, 1200000.00, 'Cash disbursement vendors Sep');

-- JE-2024-0037: Raw Material Purchases - July
INSERT INTO journal_entries VALUES (37, 'JE-2024-0037', DATE '2024-07-10', 'Raw material procurement - July', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (73, 37, 3, 2, 1450000.00, 0, 'Raw material purchases Jul');
INSERT INTO journal_lines VALUES (74, 37, 11, 2, 0, 1450000.00, 'AP for raw materials Jul');

-- JE-2024-0038: Raw Material Purchases - August
INSERT INTO journal_entries VALUES (38, 'JE-2024-0038', DATE '2024-08-10', 'Raw material procurement - August', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (75, 38, 3, 2, 1520000.00, 0, 'Raw material purchases Aug');
INSERT INTO journal_lines VALUES (76, 38, 11, 2, 0, 1520000.00, 'AP for raw materials Aug');

-- JE-2024-0039: Raw Material Purchases - September
INSERT INTO journal_entries VALUES (39, 'JE-2024-0039', DATE '2024-09-10', 'Raw material procurement - September', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (77, 39, 3, 2, 980000.00, 0, 'Raw material purchases Sep');
INSERT INTO journal_lines VALUES (78, 39, 11, 2, 0, 980000.00, 'AP for raw materials Sep');

-- JE-2024-0040: Manufacturing Overhead - July
INSERT INTO journal_entries VALUES (40, 'JE-2024-0040', DATE '2024-07-31', 'Manufacturing overhead allocation - July', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (79, 40, 25, 2, 95000.00, 0, 'Mfg overhead Jul');
INSERT INTO journal_lines VALUES (80, 40, 12, 2, 0, 95000.00, 'Accrued overhead Jul');

-- JE-2024-0041: Manufacturing Overhead - August
INSERT INTO journal_entries VALUES (41, 'JE-2024-0041', DATE '2024-08-31', 'Manufacturing overhead allocation - August', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (81, 41, 25, 2, 98000.00, 0, 'Mfg overhead Aug');
INSERT INTO journal_lines VALUES (82, 41, 12, 2, 0, 98000.00, 'Accrued overhead Aug');

-- JE-2024-0042: Manufacturing Overhead - September
INSERT INTO journal_entries VALUES (42, 'JE-2024-0042', DATE '2024-09-30', 'Manufacturing overhead allocation - September', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (83, 42, 25, 2, 92000.00, 0, 'Mfg overhead Sep');
INSERT INTO journal_lines VALUES (84, 42, 12, 2, 0, 92000.00, 'Accrued overhead Sep');

COMMIT;

EXIT;
EOSQL

# -- Batch 5: Remaining normal entries (entries 43-46, 48-54) and insurance/prepaid
sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- JE-2024-0043: Insurance Premium Q3
INSERT INTO journal_entries VALUES (43, 'JE-2024-0043', DATE '2024-07-01', 'Q3 insurance premium payment', 'A.Johnson', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (85, 43, 33, 1, 67500.00, 0, 'Insurance expense Q3');
INSERT INTO journal_lines VALUES (86, 43, 1, 1, 0, 67500.00, 'Cash payment insurance Q3');

-- JE-2024-0044: Office and Admin Expenses - July
INSERT INTO journal_entries VALUES (44, 'JE-2024-0044', DATE '2024-07-31', 'Office supplies and admin costs - July', 'L.Garcia', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (87, 44, 32, 1, 15800.00, 0, 'Office admin expenses Jul');
INSERT INTO journal_lines VALUES (88, 44, 1, 1, 0, 15800.00, 'Cash payment office Jul');

-- JE-2024-0045: Office and Admin Expenses - August
INSERT INTO journal_entries VALUES (45, 'JE-2024-0045', DATE '2024-08-31', 'Office supplies and admin costs - August', 'L.Garcia', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (89, 45, 32, 1, 14200.00, 0, 'Office admin expenses Aug');
INSERT INTO journal_lines VALUES (90, 45, 1, 1, 0, 14200.00, 'Cash payment office Aug');

-- JE-2024-0046: Office and Admin Expenses - September
INSERT INTO journal_entries VALUES (46, 'JE-2024-0046', DATE '2024-09-30', 'Office supplies and admin costs - September', 'L.Garcia', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (91, 46, 32, 1, 16500.00, 0, 'Office admin expenses Sep');
INSERT INTO journal_lines VALUES (92, 46, 1, 1, 0, 16500.00, 'Cash payment office Sep');

-- JE-2024-0048: Sales Commission Accrual Q3
INSERT INTO journal_entries VALUES (48, 'JE-2024-0048', DATE '2024-09-30', 'Q3 sales commissions accrual', 'S.Williams', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (95, 48, 31, 3, 85000.00, 0, 'Sales commissions Q3');
INSERT INTO journal_lines VALUES (96, 48, 14, 1, 0, 85000.00, 'Accrued commissions Q3');

-- JE-2024-0049: Prepaid Expense Amortization Q3
INSERT INTO journal_entries VALUES (49, 'JE-2024-0049', DATE '2024-09-30', 'Prepaid insurance amortization Q3', 'A.Johnson', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (97, 49, 33, 1, 22500.00, 0, 'Prepaid insurance amortized Q3');
INSERT INTO journal_lines VALUES (98, 49, 6, 1, 0, 22500.00, 'Prepaid expenses reduced Q3');

-- JE-2024-0050: WIP to Finished Goods Transfer - July
INSERT INTO journal_entries VALUES (50, 'JE-2024-0050', DATE '2024-07-31', 'WIP to finished goods - July production', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (99, 50, 5, 2, 2100000.00, 0, 'FG from production Jul');
INSERT INTO journal_lines VALUES (100, 50, 4, 2, 0, 2100000.00, 'WIP transferred to FG Jul');

-- JE-2024-0051: WIP to Finished Goods Transfer - August
INSERT INTO journal_entries VALUES (51, 'JE-2024-0051', DATE '2024-08-31', 'WIP to finished goods - August production', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (101, 51, 5, 2, 2200000.00, 0, 'FG from production Aug');
INSERT INTO journal_lines VALUES (102, 51, 4, 2, 0, 2200000.00, 'WIP transferred to FG Aug');

-- JE-2024-0052: Raw Materials to WIP - July
INSERT INTO journal_entries VALUES (52, 'JE-2024-0052', DATE '2024-07-31', 'Raw materials issued to production - July', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (103, 52, 4, 2, 1400000.00, 0, 'WIP from raw materials Jul');
INSERT INTO journal_lines VALUES (104, 52, 3, 2, 0, 1400000.00, 'Raw materials consumed Jul');

-- JE-2024-0053: Raw Materials to WIP - August
INSERT INTO journal_entries VALUES (53, 'JE-2024-0053', DATE '2024-08-31', 'Raw materials issued to production - August', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (105, 53, 4, 2, 1480000.00, 0, 'WIP from raw materials Aug');
INSERT INTO journal_lines VALUES (106, 53, 3, 2, 0, 1480000.00, 'Raw materials consumed Aug');

-- JE-2024-0054: Debt Principal Payment - Q3
INSERT INTO journal_entries VALUES (54, 'JE-2024-0054', DATE '2024-09-30', 'Quarterly term loan principal payment', 'A.Johnson', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (107, 54, 15, 1, 125000.00, 0, 'Long-term debt reduction Q3');
INSERT INTO journal_lines VALUES (108, 54, 1, 1, 0, 125000.00, 'Cash payment debt principal Q3');

COMMIT;

EXIT;
EOSQL

echo "Normal journal entries inserted (entries 1-54, excluding error entries)"

# ---------------------------------------------------------------
# 8. INJECT ERROR 1: Unbalanced Journal Entry (JE-2024-0047)
#    Debit to Inventory $45,000 but Credit to AP only $40,000
#    (missing $5,000 credit)
# ---------------------------------------------------------------
echo "Injecting ERROR 1: Unbalanced journal entry JE-2024-0047..."

sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

INSERT INTO journal_entries VALUES (47, 'JE-2024-0047', DATE '2024-09-15', 'Emergency inventory purchase - specialty components', 'R.Patel', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (93, 47, 3, 2, 45000.00, 0, 'Raw material inventory purchase');
INSERT INTO journal_lines VALUES (94, 47, 11, 2, 0, 40000.00, 'AP for inventory purchase');
COMMIT;

EXIT;
EOSQL
echo "  ERROR 1 injected: JE-2024-0047 unbalanced by $5,000 (debit $45K, credit $40K)"

# ---------------------------------------------------------------
# 9. INJECT ERROR 2: Duplicate Journal Entry (JE-2024-0023-DUP)
#    Exact duplicate of JE-2024-0023 with different entry_id
# ---------------------------------------------------------------
echo "Injecting ERROR 2: Duplicate journal entry JE-2024-0023-DUP..."

sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

INSERT INTO journal_entries VALUES (55, 'JE-2024-0023-DUP', DATE '2024-08-15', 'Trade show booth and marketing materials', 'L.Garcia', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (109, 55, 31, 3, 12500.00, 0, 'Trade show marketing expense');
INSERT INTO journal_lines VALUES (110, 55, 1, 1, 0, 12500.00, 'Cash payment for trade show');
COMMIT;

EXIT;
EOSQL
echo "  ERROR 2 injected: JE-2024-0023-DUP duplicates JE-2024-0023 (entry_id 55 duplicates 23)"

# ---------------------------------------------------------------
# 10. INJECT ERROR 3: Uneliminated Intercompany Transaction
#     IC sale from Parent to Subsidiary for $75,000 with no elimination
# ---------------------------------------------------------------
echo "Injecting ERROR 3: Uneliminated intercompany transaction..."

sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- Parent side: records intercompany revenue
INSERT INTO journal_entries VALUES (56, 'JE-2024-IC-003', DATE '2024-08-20', 'Intercompany sale of components to Acme Components LLC', 'M.Chen', 'POSTED', 1, 1);
INSERT INTO journal_lines VALUES (111, 56, 2, 1, 75000.00, 0, 'IC receivable from subsidiary');
INSERT INTO journal_lines VALUES (112, 56, 21, 1, 0, 75000.00, 'Intercompany revenue');

-- Subsidiary side: records intercompany purchase
INSERT INTO journal_entries VALUES (57, 'JE-2024-IC-004', DATE '2024-08-20', 'Intercompany purchase of components from Acme Manufacturing Corp', 'R.Patel', 'POSTED', 2, 1);
INSERT INTO journal_lines VALUES (113, 57, 34, 2, 75000.00, 0, 'Intercompany COGS');
INSERT INTO journal_lines VALUES (114, 57, 11, 2, 0, 75000.00, 'IC payable to parent');

-- NOTE: Deliberately NO elimination entry in INTERCOMPANY_ELIMINATIONS table
-- The agent must find this and create the elimination

COMMIT;

EXIT;
EOSQL
echo "  ERROR 3 injected: IC transaction $75,000 (entries 56,57) with NO elimination record"

# ---------------------------------------------------------------
# 11. INJECT ERROR 4: Misclassified Capital Expenditure (JE-2024-0055)
#     Equipment purchase of $25,000 debited to Utilities Expense
#     instead of PP&E (Property, Plant & Equipment)
# ---------------------------------------------------------------
echo "Injecting ERROR 4: Misclassified capital expenditure JE-2024-0055..."

sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

INSERT INTO journal_entries VALUES (58, 'JE-2024-0055', DATE '2024-09-05', 'CNC milling machine purchase - Plant expansion', 'K.Brown', 'POSTED', 1, 0);
INSERT INTO journal_lines VALUES (115, 58, 29, 2, 25000.00, 0, 'Equipment purchase - CNC machine');
INSERT INTO journal_lines VALUES (116, 58, 1, 1, 0, 25000.00, 'Cash payment for equipment');
COMMIT;

EXIT;
EOSQL
echo "  ERROR 4 injected: JE-2024-0055 equipment $25K debited to Utilities (acct 29) instead of PP&E (acct 7)"

# ---------------------------------------------------------------
# 12. Add a few properly eliminated intercompany entries as contrast
# ---------------------------------------------------------------
echo "Inserting properly eliminated intercompany entries (for contrast)..."

sudo docker exec -i oracle-xe sqlplus -s fiscal_admin/Fiscal2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

-- Earlier IC transaction that WAS properly eliminated
INSERT INTO journal_entries VALUES (59, 'JE-2024-IC-001', DATE '2024-07-15', 'Intercompany sale - management fee', 'M.Chen', 'POSTED', 1, 1);
INSERT INTO journal_lines VALUES (117, 59, 2, 1, 50000.00, 0, 'IC receivable mgmt fee');
INSERT INTO journal_lines VALUES (118, 59, 21, 1, 0, 50000.00, 'IC revenue mgmt fee');

INSERT INTO journal_entries VALUES (60, 'JE-2024-IC-002', DATE '2024-07-15', 'Intercompany purchase - management fee', 'R.Patel', 'POSTED', 2, 1);
INSERT INTO journal_lines VALUES (119, 60, 32, 1, 50000.00, 0, 'IC admin expense mgmt fee');
INSERT INTO journal_lines VALUES (120, 60, 11, 2, 0, 50000.00, 'IC payable mgmt fee');

-- Proper elimination entry
INSERT INTO intercompany_eliminations VALUES (1, 59, 60, 50000.00, 'COMPLETED');

COMMIT;

EXIT;
EOSQL
echo "  Properly eliminated IC transaction added ($50K, entries 59/60, elim_id=1)"

# ---------------------------------------------------------------
# 13. Verify data integrity
# ---------------------------------------------------------------
echo ""
echo "Verifying data integrity..."

JE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM fiscal_admin.journal_entries;" "system" | tr -d '[:space:]')
JL_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM fiscal_admin.journal_lines;" "system" | tr -d '[:space:]')
COA_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM fiscal_admin.chart_of_accounts;" "system" | tr -d '[:space:]')
ENT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM fiscal_admin.entities;" "system" | tr -d '[:space:]')
CC_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM fiscal_admin.cost_centers;" "system" | tr -d '[:space:]')
ELIM_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM fiscal_admin.intercompany_eliminations;" "system" | tr -d '[:space:]')

echo "  Journal Entries:  ${JE_COUNT}"
echo "  Journal Lines:    ${JL_COUNT}"
echo "  Chart of Accounts: ${COA_COUNT}"
echo "  Entities:         ${ENT_COUNT}"
echo "  Cost Centers:     ${CC_COUNT}"
echo "  Eliminations:     ${ELIM_COUNT}"

# Verify the 4 errors are present
echo ""
echo "Verifying injected errors..."

# Error 1: Unbalanced entry
UNBAL=$(oracle_query_raw "SELECT entry_number || ': debit=' || d || ' credit=' || c
FROM (
  SELECT je.entry_number,
         SUM(jl.debit_amount) AS d,
         SUM(jl.credit_amount) AS c
  FROM fiscal_admin.journal_entries je
  JOIN fiscal_admin.journal_lines jl ON je.entry_id = jl.entry_id
  WHERE je.entry_number = 'JE-2024-0047'
  GROUP BY je.entry_number
  HAVING SUM(jl.debit_amount) <> SUM(jl.credit_amount)
);" "system")
echo "  Error 1 (unbalanced): $UNBAL"

# Error 2: Duplicate entry
DUP=$(oracle_query_raw "SELECT COUNT(*) FROM fiscal_admin.journal_entries WHERE entry_number IN ('JE-2024-0023','JE-2024-0023-DUP');" "system" | tr -d '[:space:]')
echo "  Error 2 (duplicate): found $DUP matching entries (expected 2)"

# Error 3: Uneliminated IC
UNELIM=$(oracle_query_raw "SELECT COUNT(*) FROM fiscal_admin.journal_entries je
WHERE je.is_intercompany = 1
AND je.entry_number LIKE 'JE-2024-IC-003%'
AND NOT EXISTS (
  SELECT 1 FROM fiscal_admin.intercompany_eliminations ie
  WHERE ie.source_entry_id = je.entry_id OR ie.target_entry_id = je.entry_id
);" "system" | tr -d '[:space:]')
echo "  Error 3 (uneliminated IC): $UNELIM entries without elimination (expected 1+)"

# Error 4: Misclassified capex
MISCL=$(oracle_query_raw "SELECT je.entry_number || ': ' || ca.account_name
FROM fiscal_admin.journal_entries je
JOIN fiscal_admin.journal_lines jl ON je.entry_id = jl.entry_id
JOIN fiscal_admin.chart_of_accounts ca ON jl.account_id = ca.account_id
WHERE je.entry_number = 'JE-2024-0055'
AND jl.debit_amount > 0
AND ca.account_category = 'Expenses';" "system")
echo "  Error 4 (misclassified capex): $MISCL"

# ---------------------------------------------------------------
# 14. Record baseline state for verifier
# ---------------------------------------------------------------
echo ""
echo "Recording baseline state..."

printf '%s' "${JE_COUNT}" > /tmp/fiscal_initial_je_count
printf '%s' "${JL_COUNT}" > /tmp/fiscal_initial_jl_count

# Ensure export directory exists
sudo -u ga mkdir -p /home/ga/Documents/exports 2>/dev/null || mkdir -p /home/ga/Documents/exports 2>/dev/null || true

# ---------------------------------------------------------------
# 15. Pre-configure SQL Developer connection for fiscal_admin
# ---------------------------------------------------------------
echo "Configuring SQL Developer connection..."

ensure_hr_connection "HR Database" "hr" "$HR_PWD"

# Also add the fiscal_admin connection
SQLDEVELOPER_SYSTEM_DIR=$(find /home/ga/.sqldeveloper -maxdepth 1 -name "system*" -type d 2>/dev/null | head -1)
if [ -n "$SQLDEVELOPER_SYSTEM_DIR" ]; then
    CONN_DIR=$(find "$SQLDEVELOPER_SYSTEM_DIR" -name "o.jdeveloper.db.connection*" -type d 2>/dev/null | head -1)
    if [ -z "$CONN_DIR" ]; then
        CONN_DIR="$SQLDEVELOPER_SYSTEM_DIR/o.jdeveloper.db.connection.24.2.0.284.2209"
        mkdir -p "$CONN_DIR"
    fi
    CONN_FILE="$CONN_DIR/connections.json"
    cat > "$CONN_FILE" << CONNEOF
{
  "connections": [
    {
      "name": "HR Database",
      "type": "jdbc",
      "info": {
        "role": "",
        "SavePassword": "true",
        "OracleConnectionType": "BASIC",
        "RaptorConnectionType": "Oracle",
        "customUrl": "jdbc:oracle:thin:@localhost:1521/XEPDB1",
        "hostname": "localhost",
        "driver": "oracle.jdbc.OracleDriver",
        "port": "1521",
        "subtype": "oraJDBC",
        "ConnName": "HR Database",
        "serviceName": "XEPDB1",
        "user": "hr",
        "password": "hr123"
      }
    },
    {
      "name": "Fiscal Admin",
      "type": "jdbc",
      "info": {
        "role": "",
        "SavePassword": "true",
        "OracleConnectionType": "BASIC",
        "RaptorConnectionType": "Oracle",
        "customUrl": "jdbc:oracle:thin:@localhost:1521/XEPDB1",
        "hostname": "localhost",
        "driver": "oracle.jdbc.OracleDriver",
        "port": "1521",
        "subtype": "oraJDBC",
        "ConnName": "Fiscal Admin",
        "serviceName": "XEPDB1",
        "user": "fiscal_admin",
        "password": "Fiscal2024"
      }
    }
  ]
}
CONNEOF
    chown ga:ga "$CONN_FILE"
    echo "  Fiscal Admin connection pre-configured"
fi

# ---------------------------------------------------------------
# 16. Ensure SQL Developer is running and take initial screenshot
# ---------------------------------------------------------------
sleep 2

if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
    echo "SQL Developer is running and focused"
fi

# Take initial screenshot
take_screenshot /tmp/fiscal_setup_initial.png
echo "Initial screenshot saved"

echo ""
echo "=== Fiscal Period Close Reconciliation setup complete ==="
echo ""
echo "Summary:"
echo "  Schema: fiscal_admin/Fiscal2024 on XEPDB1"
echo "  Tables: entities(2), chart_of_accounts(${COA_COUNT}), cost_centers(3),"
echo "          journal_entries(${JE_COUNT}), journal_lines(${JL_COUNT}),"
echo "          intercompany_eliminations(${ELIM_COUNT})"
echo ""
echo "  INJECTED ERRORS (4 total):"
echo "    1. JE-2024-0047: Unbalanced entry (debit $45K vs credit $40K)"
echo "    2. JE-2024-0023-DUP: Duplicate of JE-2024-0023"
echo "    3. JE-2024-IC-003/IC-004: Intercompany $75K not eliminated"
echo "    4. JE-2024-0055: Equipment $25K misclassified as Utilities Expense"
