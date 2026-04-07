#!/bin/bash
# Setup script for SaaS Billing Reconciliation task
echo "=== Setting up SaaS Billing Reconciliation Task ==="

source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# 0. Delete stale outputs BEFORE recording timestamp
# ---------------------------------------------------------------
rm -f /home/ga/Documents/exports/billing_reconciliation.csv 2>/dev/null || true
rm -f /tmp/billing_reconciliation_result.json 2>/dev/null || true

# Record task start time
date +%s > /home/ga/.task_start_time

# ---------------------------------------------------------------
# 1. Verify Oracle is running
# ---------------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# ---------------------------------------------------------------
# 2. Clean up previous run artifacts
# ---------------------------------------------------------------
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER billing_ops CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true
sleep 2

# ---------------------------------------------------------------
# 3. Create BILLING_OPS schema
# ---------------------------------------------------------------
echo "Creating BILLING_OPS schema..."
oracle_query "CREATE USER billing_ops IDENTIFIED BY Billing2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO billing_ops;
GRANT RESOURCE TO billing_ops;
GRANT CREATE VIEW TO billing_ops;
GRANT CREATE MATERIALIZED VIEW TO billing_ops;
GRANT CREATE SESSION TO billing_ops;
GRANT CREATE TABLE TO billing_ops;
GRANT CREATE PROCEDURE TO billing_ops;
GRANT CREATE SEQUENCE TO billing_ops;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create billing_ops user"
    exit 1
fi

# ---------------------------------------------------------------
# 4. Create tables, sequences, and load all data
# ---------------------------------------------------------------
echo "Creating tables and loading data..."

sudo docker exec -i oracle-xe sqlplus -s billing_ops/Billing2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF

-- ============================================================
-- TABLE DEFINITIONS
-- ============================================================

CREATE TABLE customers (
  customer_id   NUMBER PRIMARY KEY,
  company_name  VARCHAR2(100) NOT NULL,
  segment       VARCHAR2(20) NOT NULL CHECK (segment IN ('STARTUP','SMB','ENTERPRISE')),
  industry      VARCHAR2(50),
  created_date  DATE DEFAULT SYSDATE
);

CREATE TABLE subscription_plans (
  plan_id       NUMBER PRIMARY KEY,
  plan_name     VARCHAR2(50) NOT NULL,
  plan_type     VARCHAR2(20) NOT NULL CHECK (plan_type IN ('FLAT','PER_SEAT','USAGE_BASED','HYBRID')),
  base_rate     NUMBER(10,2) DEFAULT 0,
  per_seat_rate NUMBER(10,2) DEFAULT 0,
  usage_unit    VARCHAR2(30)
);

CREATE TABLE subscriptions (
  subscription_id NUMBER PRIMARY KEY,
  customer_id     NUMBER REFERENCES customers(customer_id),
  plan_id         NUMBER REFERENCES subscription_plans(plan_id),
  start_date      DATE NOT NULL,
  end_date        DATE,
  seat_count      NUMBER DEFAULT 0,
  status          VARCHAR2(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','CANCELLED','UPGRADED'))
);

CREATE TABLE usage_meters (
  meter_id      NUMBER PRIMARY KEY,
  customer_id   NUMBER REFERENCES customers(customer_id),
  billing_month DATE NOT NULL,
  meter_type    VARCHAR2(30) NOT NULL,
  quantity      NUMBER NOT NULL
);

CREATE TABLE invoices (
  invoice_id    NUMBER PRIMARY KEY,
  customer_id   NUMBER REFERENCES customers(customer_id),
  billing_month DATE NOT NULL,
  invoice_date  DATE NOT NULL,
  total_amount  NUMBER(12,2) NOT NULL,
  status        VARCHAR2(20) DEFAULT 'PAID'
);

CREATE TABLE invoice_line_items (
  line_id     NUMBER PRIMARY KEY,
  invoice_id  NUMBER REFERENCES invoices(invoice_id),
  description VARCHAR2(200),
  quantity    NUMBER,
  unit_price  NUMBER(10,4),
  line_total  NUMBER(12,2),
  line_type   VARCHAR2(20) CHECK (line_type IN ('BASE','SEAT','USAGE','CREDIT','PRORATION'))
);

CREATE TABLE pricing_tiers (
  tier_id       NUMBER PRIMARY KEY,
  plan_id       NUMBER REFERENCES subscription_plans(plan_id),
  meter_type    VARCHAR2(30) NOT NULL,
  min_quantity  NUMBER NOT NULL,
  max_quantity  NUMBER,
  rate_per_unit NUMBER(10,6) NOT NULL
);

CREATE TABLE promotional_credits (
  credit_id     NUMBER PRIMARY KEY,
  customer_id   NUMBER REFERENCES customers(customer_id),
  credit_type   VARCHAR2(30) NOT NULL,
  credit_amount NUMBER(10,2) NOT NULL,
  start_date    DATE NOT NULL,
  expiry_date   DATE NOT NULL,
  is_percentage CHAR(1) DEFAULT 'N' CHECK (is_percentage IN ('Y','N'))
);

CREATE SEQUENCE invoice_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE line_item_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE meter_seq START WITH 1 INCREMENT BY 1;

-- ============================================================
-- SUBSCRIPTION PLANS (6 plans)
-- ============================================================
INSERT INTO subscription_plans VALUES (1, 'Starter',         'FLAT',        49.00,   0,    NULL);
INSERT INTO subscription_plans VALUES (2, 'Team',            'PER_SEAT',     0,     15.00, NULL);
INSERT INTO subscription_plans VALUES (3, 'Business',        'HYBRID',      29.00,  12.00, 'API_CALLS');
INSERT INTO subscription_plans VALUES (4, 'Professional',    'USAGE_BASED',  0,      0,    'API_CALLS');
INSERT INTO subscription_plans VALUES (5, 'Enterprise',      'HYBRID',     499.00,   0,    'API_CALLS');
INSERT INTO subscription_plans VALUES (6, 'Enterprise Plus', 'HYBRID',     999.00,   0,    'COMPUTE_HOURS');

-- ============================================================
-- PRICING TIERS (graduated brackets)
-- ============================================================
-- API_CALLS tiers for plans 3, 4, 5
INSERT INTO pricing_tiers VALUES ( 1, 3, 'API_CALLS',      0, 10000,  0.001000);
INSERT INTO pricing_tiers VALUES ( 2, 3, 'API_CALLS',  10001, 100000, 0.000800);
INSERT INTO pricing_tiers VALUES ( 3, 3, 'API_CALLS', 100001, NULL,   0.000500);
INSERT INTO pricing_tiers VALUES ( 4, 4, 'API_CALLS',      0, 10000,  0.001000);
INSERT INTO pricing_tiers VALUES ( 5, 4, 'API_CALLS',  10001, 100000, 0.000800);
INSERT INTO pricing_tiers VALUES ( 6, 4, 'API_CALLS', 100001, NULL,   0.000500);
INSERT INTO pricing_tiers VALUES ( 7, 5, 'API_CALLS',      0, 10000,  0.001000);
INSERT INTO pricing_tiers VALUES ( 8, 5, 'API_CALLS',  10001, 100000, 0.000800);
INSERT INTO pricing_tiers VALUES ( 9, 5, 'API_CALLS', 100001, NULL,   0.000500);
-- STORAGE_GB tiers for plan 5
INSERT INTO pricing_tiers VALUES (10, 5, 'STORAGE_GB',     0,   100,  0.100000);
INSERT INTO pricing_tiers VALUES (11, 5, 'STORAGE_GB',   101,  1000,  0.070000);
INSERT INTO pricing_tiers VALUES (12, 5, 'STORAGE_GB',  1001,  NULL,  0.040000);
-- COMPUTE_HOURS tiers for plan 6
INSERT INTO pricing_tiers VALUES (13, 6, 'COMPUTE_HOURS',   0,  100,  2.500000);
INSERT INTO pricing_tiers VALUES (14, 6, 'COMPUTE_HOURS', 101,  500,  2.000000);
INSERT INTO pricing_tiers VALUES (15, 6, 'COMPUTE_HOURS', 501, NULL,  1.500000);

-- ============================================================
-- CUSTOMERS (30 customers across 3 segments)
-- ============================================================
-- STARTUP segment (customers 1-5)
INSERT INTO customers VALUES ( 1, 'NovaTech Solutions',        'STARTUP',    'Technology',       DATE '2024-03-01');
INSERT INTO customers VALUES ( 2, 'Pixel & Code LLC',          'STARTUP',    'Software',         DATE '2024-06-15');
INSERT INTO customers VALUES ( 3, 'GreenLeaf Analytics',       'STARTUP',    'Data Analytics',   DATE '2024-01-01');
INSERT INTO customers VALUES ( 4, 'SwiftShip Logistics',       'STARTUP',    'Logistics',        DATE '2024-09-01');
INSERT INTO customers VALUES ( 5, 'BrightPath Learning',       'STARTUP',    'Education',        DATE '2024-04-01');
-- SMB segment (customers 6-20)
INSERT INTO customers VALUES ( 6, 'Meridian Healthcare Group', 'SMB',        'Healthcare',       DATE '2023-11-01');
INSERT INTO customers VALUES ( 7, 'Atlas Manufacturing Co',    'SMB',        'Manufacturing',    DATE '2024-02-01');
INSERT INTO customers VALUES ( 8, 'Coastal Realty Partners',   'SMB',        'Real Estate',      DATE '2024-05-01');
INSERT INTO customers VALUES ( 9, 'Summit Financial Advisors', 'SMB',        'Finance',          DATE '2024-03-01');
INSERT INTO customers VALUES (10, 'TrueNorth Marketing',       'SMB',        'Marketing',        DATE '2024-07-01');
INSERT INTO customers VALUES (11, 'Pinnacle Engineering',      'SMB',        'Engineering',      DATE '2024-08-01');
INSERT INTO customers VALUES (12, 'Heritage Foods Inc',        'SMB',        'Food & Beverage',  DATE '2024-01-15');
INSERT INTO customers VALUES (13, 'ClearView Consulting',      'SMB',        'Consulting',       DATE '2024-06-01');
INSERT INTO customers VALUES (14, 'Riverdale Property Mgmt',   'SMB',        'Property Mgmt',    DATE '2024-04-01');
INSERT INTO customers VALUES (15, 'NextGen Retail Corp',       'SMB',        'Retail',           DATE '2024-02-01');
INSERT INTO customers VALUES (16, 'ProScale Dynamics',         'SMB',        'Manufacturing',    DATE '2024-09-01');
INSERT INTO customers VALUES (17, 'DataForge Systems',         'SMB',        'Technology',       DATE '2024-01-01');
INSERT INTO customers VALUES (18, 'Quantum Analytics Corp',    'SMB',        'Data Analytics',   DATE '2024-05-01');
INSERT INTO customers VALUES (19, 'Redwood Creative Agency',   'SMB',        'Media',            DATE '2024-07-01');
INSERT INTO customers VALUES (20, 'Alpine Sports Equipment',   'SMB',        'Retail',           DATE '2024-03-01');
-- ENTERPRISE segment (customers 21-30)
INSERT INTO customers VALUES (21, 'GlobalTech Industries',     'ENTERPRISE', 'Technology',       DATE '2023-06-01');
INSERT INTO customers VALUES (22, 'Pacific Rim Trading Co',    'ENTERPRISE', 'Import/Export',    DATE '2024-01-01');
INSERT INTO customers VALUES (23, 'Continental Insurance Grp', 'ENTERPRISE', 'Insurance',        DATE '2023-09-01');
INSERT INTO customers VALUES (24, 'MetroCity Utilities Corp',  'ENTERPRISE', 'Utilities',        DATE '2023-03-01');
INSERT INTO customers VALUES (25, 'Transcontinental Logistics','ENTERPRISE', 'Logistics',        DATE '2024-04-01');
INSERT INTO customers VALUES (26, 'National Grid Services',    'ENTERPRISE', 'Energy',           DATE '2023-01-01');
INSERT INTO customers VALUES (27, 'United Healthcare Systems', 'ENTERPRISE', 'Healthcare',       DATE '2024-02-01');
INSERT INTO customers VALUES (28, 'Federal Defense Solutions',  'ENTERPRISE', 'Government',       DATE '2023-08-01');
INSERT INTO customers VALUES (29, 'Consolidated Media Group',  'ENTERPRISE', 'Media',            DATE '2024-06-01');
INSERT INTO customers VALUES (30, 'InterBank Financial Corp',  'ENTERPRISE', 'Banking',          DATE '2024-07-01');

-- ============================================================
-- SUBSCRIPTIONS (32 rows, including 2 upgrades)
-- ============================================================
INSERT INTO subscriptions VALUES ( 1,  1, 1, DATE '2024-03-01', NULL,            1, 'ACTIVE');
INSERT INTO subscriptions VALUES ( 2,  2, 1, DATE '2024-06-15', NULL,            1, 'ACTIVE');
INSERT INTO subscriptions VALUES ( 3,  3, 3, DATE '2024-01-01', NULL,            3, 'ACTIVE');
INSERT INTO subscriptions VALUES ( 4,  4, 1, DATE '2024-09-01', NULL,            1, 'ACTIVE');
INSERT INTO subscriptions VALUES ( 5,  5, 2, DATE '2024-04-01', NULL,            5, 'ACTIVE');
INSERT INTO subscriptions VALUES ( 6,  6, 2, DATE '2023-11-01', NULL,            8, 'ACTIVE');
INSERT INTO subscriptions VALUES ( 7,  7, 1, DATE '2024-02-01', DATE '2025-01-14', 1, 'UPGRADED');
INSERT INTO subscriptions VALUES ( 8,  7, 2, DATE '2025-01-15', NULL,           10, 'ACTIVE');
INSERT INTO subscriptions VALUES ( 9,  8, 2, DATE '2024-05-01', NULL,           10, 'ACTIVE');
INSERT INTO subscriptions VALUES (10,  9, 3, DATE '2024-03-01', NULL,            5, 'ACTIVE');
INSERT INTO subscriptions VALUES (11, 10, 2, DATE '2024-07-01', NULL,            6, 'ACTIVE');
INSERT INTO subscriptions VALUES (12, 11, 3, DATE '2024-08-01', NULL,            4, 'ACTIVE');
INSERT INTO subscriptions VALUES (13, 12, 2, DATE '2024-01-15', NULL,            7, 'ACTIVE');
INSERT INTO subscriptions VALUES (14, 13, 4, DATE '2024-06-01', NULL,            0, 'ACTIVE');
INSERT INTO subscriptions VALUES (15, 14, 2, DATE '2024-04-01', DATE '2024-12-31', 8, 'CANCELLED');
INSERT INTO subscriptions VALUES (16, 15, 3, DATE '2024-02-01', NULL,            6, 'ACTIVE');
INSERT INTO subscriptions VALUES (17, 16, 4, DATE '2024-09-01', NULL,            0, 'ACTIVE');
INSERT INTO subscriptions VALUES (18, 17, 3, DATE '2024-01-01', NULL,            8, 'ACTIVE');
INSERT INTO subscriptions VALUES (19, 18, 4, DATE '2024-05-01', NULL,            0, 'ACTIVE');
INSERT INTO subscriptions VALUES (20, 19, 3, DATE '2024-07-01', NULL,            3, 'ACTIVE');
INSERT INTO subscriptions VALUES (21, 20, 2, DATE '2024-03-01', DATE '2025-02-09', 5, 'UPGRADED');
INSERT INTO subscriptions VALUES (22, 20, 3, DATE '2025-02-10', NULL,            5, 'ACTIVE');
INSERT INTO subscriptions VALUES (23, 21, 5, DATE '2023-06-01', NULL,            0, 'ACTIVE');
INSERT INTO subscriptions VALUES (24, 22, 5, DATE '2024-01-01', NULL,            0, 'ACTIVE');
INSERT INTO subscriptions VALUES (25, 23, 5, DATE '2023-09-01', NULL,            0, 'ACTIVE');
INSERT INTO subscriptions VALUES (26, 24, 6, DATE '2023-03-01', NULL,            0, 'ACTIVE');
INSERT INTO subscriptions VALUES (27, 25, 5, DATE '2024-04-01', NULL,            0, 'ACTIVE');
INSERT INTO subscriptions VALUES (28, 26, 6, DATE '2023-01-01', NULL,            0, 'ACTIVE');
INSERT INTO subscriptions VALUES (29, 27, 5, DATE '2024-02-01', NULL,            0, 'ACTIVE');
INSERT INTO subscriptions VALUES (30, 28, 6, DATE '2023-08-01', NULL,            0, 'ACTIVE');
INSERT INTO subscriptions VALUES (31, 29, 5, DATE '2024-06-01', NULL,            0, 'ACTIVE');
INSERT INTO subscriptions VALUES (32, 30, 5, DATE '2024-07-01', NULL,            0, 'ACTIVE');

-- ============================================================
-- PROMOTIONAL CREDITS (8 credits, 2 with past expiry dates)
-- ============================================================
INSERT INTO promotional_credits VALUES (1, 10, 'SIGNUP_BONUS',    50.00, DATE '2024-07-01', DATE '2024-12-31', 'N');
INSERT INTO promotional_credits VALUES (2, 27, 'REFERRAL',        25.00, DATE '2024-08-01', DATE '2024-11-30', 'N');
INSERT INTO promotional_credits VALUES (3,  2, 'ANNUAL_DISCOUNT', 10.00, DATE '2024-01-01', DATE '2025-12-31', 'Y');
INSERT INTO promotional_credits VALUES (4, 21, 'LOYALTY',        100.00, DATE '2024-01-01', DATE '2025-06-30', 'N');
INSERT INTO promotional_credits VALUES (5, 23, 'REFERRAL',        50.00, DATE '2024-09-01', DATE '2025-03-31', 'N');
INSERT INTO promotional_credits VALUES (6,  6, 'SIGNUP_BONUS',    30.00, DATE '2024-11-01', DATE '2025-04-30', 'N');
INSERT INTO promotional_credits VALUES (7, 17, 'ANNUAL_DISCOUNT',  5.00, DATE '2024-01-01', DATE '2025-12-31', 'Y');
INSERT INTO promotional_credits VALUES (8, 29, 'REFERRAL',        75.00, DATE '2024-06-01', DATE '2025-02-28', 'N');

COMMIT;

-- ============================================================
-- GENERATE USAGE METERS (deterministic monthly usage)
-- ============================================================
DECLARE
  v_mid NUMBER := 1;
  PROCEDURE add_usage(p_cust NUMBER, p_type VARCHAR2, p_qty NUMBER) IS
  BEGIN
    FOR m IN 0..5 LOOP
      INSERT INTO usage_meters VALUES (v_mid, p_cust, ADD_MONTHS(DATE '2024-10-01', m), p_type, p_qty);
      v_mid := v_mid + 1;
    END LOOP;
  END;
BEGIN
  -- Business (plan 3) customers: API_CALLS
  add_usage( 3, 'API_CALLS',  15000);
  add_usage( 9, 'API_CALLS',   8000);
  add_usage(11, 'API_CALLS',   5000);
  add_usage(15, 'API_CALLS',  10000);
  add_usage(17, 'API_CALLS',  20000);
  add_usage(19, 'API_CALLS',   3000);
  -- Professional (plan 4) customers: API_CALLS
  add_usage(13, 'API_CALLS',  25000);
  add_usage(16, 'API_CALLS',  50000);
  add_usage(18, 'API_CALLS', 120000);
  -- Enterprise (plan 5) customers: API_CALLS
  add_usage(21, 'API_CALLS', 200000);
  add_usage(22, 'API_CALLS',  80000);
  add_usage(23, 'API_CALLS', 150000);
  add_usage(27, 'API_CALLS', 100000);
  add_usage(29, 'API_CALLS',  60000);
  add_usage(30, 'API_CALLS',  30000);
  -- Enterprise (plan 5) customer 25: STORAGE_GB
  add_usage(25, 'STORAGE_GB',   500);
  -- Enterprise Plus (plan 6) customers: COMPUTE_HOURS
  add_usage(24, 'COMPUTE_HOURS', 300);
  add_usage(26, 'COMPUTE_HOURS', 600);
  add_usage(28, 'COMPUTE_HOURS', 200);
  -- Customer 20: usage only after upgrade to Business (Feb-Mar 2025)
  INSERT INTO usage_meters VALUES (v_mid, 20, DATE '2025-02-01', 'API_CALLS', 12000);
  v_mid := v_mid + 1;
  INSERT INTO usage_meters VALUES (v_mid, 20, DATE '2025-03-01', 'API_CALLS', 12000);
  COMMIT;
END;
/

-- ============================================================
-- GENERATE INVOICES AND LINE ITEMS
-- Uses graduated tier pricing, credits, and current subscriptions.
-- Invoices use the subscription active at the START of the month.
-- This naturally produces PRORATION_ERRORs for mid-month upgrades.
-- ============================================================
DECLARE
  v_base         NUMBER;
  v_seat_charge  NUMBER;
  v_usage_charge NUMBER;
  v_tier_charge  NUMBER;
  v_credit_total NUMBER;
  v_total        NUMBER;
  v_remaining    NUMBER;
  v_band         NUMBER;
  v_inv_id       NUMBER;
BEGIN
  FOR month_idx IN 0..5 LOOP
    DECLARE
      v_bm DATE := ADD_MONTHS(DATE '2024-10-01', month_idx);
    BEGIN
      FOR sub IN (
        SELECT s.customer_id, s.plan_id, s.seat_count,
               sp.plan_name, sp.plan_type, sp.base_rate,
               NVL(sp.per_seat_rate, 0) AS per_seat_rate
        FROM subscriptions s
        JOIN subscription_plans sp ON s.plan_id = sp.plan_id
        WHERE v_bm >= s.start_date
        AND   v_bm < NVL(s.end_date, DATE '2099-12-31') + 1
      ) LOOP
        -- Base + seat charges
        v_base := NVL(sub.base_rate, 0);
        v_seat_charge := sub.per_seat_rate * NVL(sub.seat_count, 0);
        v_usage_charge := 0;

        -- Graduated usage pricing
        IF sub.plan_type IN ('USAGE_BASED', 'HYBRID') THEN
          FOR um IN (
            SELECT meter_type, quantity FROM usage_meters
            WHERE customer_id = sub.customer_id AND billing_month = v_bm
          ) LOOP
            v_tier_charge := 0;
            v_remaining := um.quantity;
            FOR tier IN (
              SELECT min_quantity, NVL(max_quantity, 999999999) AS max_quantity, rate_per_unit
              FROM pricing_tiers
              WHERE plan_id = sub.plan_id AND meter_type = um.meter_type
              ORDER BY min_quantity
            ) LOOP
              EXIT WHEN v_remaining <= 0;
              IF tier.min_quantity = 0 THEN
                v_band := LEAST(v_remaining, tier.max_quantity);
              ELSE
                v_band := LEAST(v_remaining, tier.max_quantity - tier.min_quantity + 1);
              END IF;
              v_tier_charge := v_tier_charge + v_band * tier.rate_per_unit;
              v_remaining := v_remaining - v_band;
            END LOOP;
            v_usage_charge := v_usage_charge + ROUND(v_tier_charge, 2);
          END LOOP;
        END IF;

        -- Apply active promotional credits
        v_credit_total := 0;
        FOR cr IN (
          SELECT credit_amount, is_percentage FROM promotional_credits
          WHERE customer_id = sub.customer_id
          AND v_bm >= start_date AND v_bm <= expiry_date
        ) LOOP
          IF cr.is_percentage = 'Y' THEN
            v_credit_total := v_credit_total +
              ROUND((v_base + v_seat_charge + v_usage_charge) * cr.credit_amount / 100, 2);
          ELSE
            v_credit_total := v_credit_total + cr.credit_amount;
          END IF;
        END LOOP;

        v_total := ROUND(v_base + v_seat_charge + v_usage_charge - v_credit_total, 2);

        -- Insert invoice
        INSERT INTO invoices VALUES (
          invoice_seq.NEXTVAL, sub.customer_id, v_bm, v_bm + 1, v_total, 'PAID'
        );
        SELECT MAX(invoice_id) INTO v_inv_id FROM invoices
        WHERE customer_id = sub.customer_id AND billing_month = v_bm;

        -- Insert line items
        IF v_base > 0 THEN
          INSERT INTO invoice_line_items VALUES (
            line_item_seq.NEXTVAL, v_inv_id,
            'Base - ' || sub.plan_name, 1, v_base, v_base, 'BASE'
          );
        END IF;
        IF v_seat_charge > 0 THEN
          INSERT INTO invoice_line_items VALUES (
            line_item_seq.NEXTVAL, v_inv_id,
            'Seats (' || sub.seat_count || ')',
            sub.seat_count, sub.per_seat_rate, v_seat_charge, 'SEAT'
          );
        END IF;
        IF v_usage_charge > 0 THEN
          INSERT INTO invoice_line_items VALUES (
            line_item_seq.NEXTVAL, v_inv_id,
            'Usage charges', 1, v_usage_charge, v_usage_charge, 'USAGE'
          );
        END IF;
        IF v_credit_total > 0 THEN
          INSERT INTO invoice_line_items VALUES (
            line_item_seq.NEXTVAL, v_inv_id,
            'Promotional credit', 1, -v_credit_total, -v_credit_total, 'CREDIT'
          );
        END IF;
      END LOOP;
    END;
  END LOOP;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Invoices generated successfully');
END;
/

-- ============================================================
-- INJECT 13 BILLING DISCREPANCIES
-- ============================================================

-- --- 1-3: MISSED_INVOICE (delete 3 invoices) ---
-- Customer 5, Feb 2025
DELETE FROM invoice_line_items WHERE invoice_id = (
  SELECT invoice_id FROM invoices WHERE customer_id = 5 AND billing_month = DATE '2025-02-01'
);
DELETE FROM invoices WHERE customer_id = 5 AND billing_month = DATE '2025-02-01';

-- Customer 12, Jan 2025
DELETE FROM invoice_line_items WHERE invoice_id = (
  SELECT invoice_id FROM invoices WHERE customer_id = 12 AND billing_month = DATE '2025-01-01'
);
DELETE FROM invoices WHERE customer_id = 12 AND billing_month = DATE '2025-01-01';

-- Customer 22, Dec 2024
DELETE FROM invoice_line_items WHERE invoice_id = (
  SELECT invoice_id FROM invoices WHERE customer_id = 22 AND billing_month = DATE '2024-12-01'
);
DELETE FROM invoices WHERE customer_id = 22 AND billing_month = DATE '2024-12-01';

-- --- 4-5: DUPLICATE_INVOICE (duplicate 2 invoices) ---
-- Customer 8, Nov 2024: insert duplicate invoice
INSERT INTO invoices (invoice_id, customer_id, billing_month, invoice_date, total_amount, status)
SELECT invoice_seq.NEXTVAL, customer_id, billing_month, invoice_date + 1, total_amount, 'PAID'
FROM invoices WHERE customer_id = 8 AND billing_month = DATE '2024-11-01' AND ROWNUM = 1;

-- Duplicate line items for customer 8 Nov duplicate
DECLARE
  v_orig_inv NUMBER;
  v_dup_inv  NUMBER;
BEGIN
  SELECT MIN(invoice_id) INTO v_orig_inv FROM invoices WHERE customer_id = 8 AND billing_month = DATE '2024-11-01';
  SELECT MAX(invoice_id) INTO v_dup_inv  FROM invoices WHERE customer_id = 8 AND billing_month = DATE '2024-11-01';
  FOR li IN (SELECT description, quantity, unit_price, line_total, line_type
             FROM invoice_line_items WHERE invoice_id = v_orig_inv) LOOP
    INSERT INTO invoice_line_items VALUES (
      line_item_seq.NEXTVAL, v_dup_inv, li.description, li.quantity, li.unit_price, li.line_total, li.line_type
    );
  END LOOP;
END;
/

-- Customer 15, Jan 2025: insert duplicate invoice
INSERT INTO invoices (invoice_id, customer_id, billing_month, invoice_date, total_amount, status)
SELECT invoice_seq.NEXTVAL, customer_id, billing_month, invoice_date + 1, total_amount, 'PAID'
FROM invoices WHERE customer_id = 15 AND billing_month = DATE '2025-01-01' AND ROWNUM = 1;

DECLARE
  v_orig_inv NUMBER;
  v_dup_inv  NUMBER;
BEGIN
  SELECT MIN(invoice_id) INTO v_orig_inv FROM invoices WHERE customer_id = 15 AND billing_month = DATE '2025-01-01';
  SELECT MAX(invoice_id) INTO v_dup_inv  FROM invoices WHERE customer_id = 15 AND billing_month = DATE '2025-01-01';
  FOR li IN (SELECT description, quantity, unit_price, line_total, line_type
             FROM invoice_line_items WHERE invoice_id = v_orig_inv) LOOP
    INSERT INTO invoice_line_items VALUES (
      line_item_seq.NEXTVAL, v_dup_inv, li.description, li.quantity, li.unit_price, li.line_total, li.line_type
    );
  END LOOP;
END;
/

-- --- 6-8: WRONG_TIER (overcharge by using flat rate instead of graduated) ---
-- Customer 3, Dec 2024: 15000 API calls billed at flat $0.001 = $15.00 instead of graduated $14.00
-- Difference: +$1.00 on usage, +$1.00 on total
UPDATE invoices SET total_amount = total_amount + 1.00
WHERE customer_id = 3 AND billing_month = DATE '2024-12-01';
UPDATE invoice_line_items SET unit_price = 15.00, line_total = 15.00
WHERE invoice_id = (SELECT invoice_id FROM invoices WHERE customer_id = 3 AND billing_month = DATE '2024-12-01')
AND line_type = 'USAGE';

-- Customer 18, Feb 2025: 120000 API calls billed at flat $0.0008 = $96.00 instead of graduated $92.00
-- Difference: +$4.00
UPDATE invoices SET total_amount = total_amount + 4.00
WHERE customer_id = 18 AND billing_month = DATE '2025-02-01';
UPDATE invoice_line_items SET unit_price = 96.00, line_total = 96.00
WHERE invoice_id = (SELECT invoice_id FROM invoices WHERE customer_id = 18 AND billing_month = DATE '2025-02-01')
AND line_type = 'USAGE';

-- Customer 25, Jan 2025: 500 GB storage billed at flat $0.10 = $50.00 instead of graduated $38.00
-- Difference: +$12.00
UPDATE invoices SET total_amount = total_amount + 12.00
WHERE customer_id = 25 AND billing_month = DATE '2025-01-01';
UPDATE invoice_line_items SET unit_price = 50.00, line_total = 50.00
WHERE invoice_id = (SELECT invoice_id FROM invoices WHERE customer_id = 25 AND billing_month = DATE '2025-01-01')
AND line_type = 'USAGE';

-- --- 9-10: PRORATION_ERROR ---
-- These are naturally generated: customer 7 (Jan 2025) and customer 20 (Feb 2025)
-- are billed at the old subscription rate because the invoice logic uses the sub
-- active at the start of the month, ignoring the mid-month upgrade.
-- No additional SQL needed.

-- --- 11-12: EXPIRED_PROMO (apply expired credits to reduce invoice incorrectly) ---
-- Customer 10, Jan 2025: $50 signup bonus expired Dec 31 but still applied
UPDATE invoices SET total_amount = total_amount - 50.00
WHERE customer_id = 10 AND billing_month = DATE '2025-01-01';
INSERT INTO invoice_line_items (line_id, invoice_id, description, quantity, unit_price, line_total, line_type)
SELECT line_item_seq.NEXTVAL, invoice_id, 'Signup bonus credit (expired)', 1, -50.00, -50.00, 'CREDIT'
FROM invoices WHERE customer_id = 10 AND billing_month = DATE '2025-01-01';

-- Customer 27, Dec 2024: $25 referral credit expired Nov 30 but still applied
UPDATE invoices SET total_amount = total_amount - 25.00
WHERE customer_id = 27 AND billing_month = DATE '2024-12-01';
INSERT INTO invoice_line_items (line_id, invoice_id, description, quantity, unit_price, line_total, line_type)
SELECT line_item_seq.NEXTVAL, invoice_id, 'Referral credit (expired)', 1, -25.00, -25.00, 'CREDIT'
FROM invoices WHERE customer_id = 27 AND billing_month = DATE '2024-12-01';

-- --- 13: POST_CANCEL_BILLING ---
-- Customer 14 cancelled Dec 31, 2024 but has invoice for Jan 2025
INSERT INTO invoices VALUES (
  invoice_seq.NEXTVAL, 14, DATE '2025-01-01', DATE '2025-01-02', 120.00, 'PAID'
);
DECLARE
  v_pc_inv NUMBER;
BEGIN
  SELECT invoice_id INTO v_pc_inv FROM invoices
  WHERE customer_id = 14 AND billing_month = DATE '2025-01-01' AND ROWNUM = 1;
  INSERT INTO invoice_line_items VALUES (
    line_item_seq.NEXTVAL, v_pc_inv, 'Seats (8)', 8, 15.00, 120.00, 'SEAT'
  );
END;
/

COMMIT;

-- Verify data counts
SELECT 'CUSTOMERS: ' || COUNT(*) FROM customers;
SELECT 'SUBSCRIPTIONS: ' || COUNT(*) FROM subscriptions;
SELECT 'USAGE_METERS: ' || COUNT(*) FROM usage_meters;
SELECT 'INVOICES: ' || COUNT(*) FROM invoices;
SELECT 'LINE_ITEMS: ' || COUNT(*) FROM invoice_line_items;
SELECT 'PRICING_TIERS: ' || COUNT(*) FROM pricing_tiers;
SELECT 'CREDITS: ' || COUNT(*) FROM promotional_credits;

EXIT;
EOSQL

echo "Data loaded successfully."

# ---------------------------------------------------------------
# 5. Ensure export directory exists
# ---------------------------------------------------------------
sudo -u ga mkdir -p /home/ga/Documents/exports 2>/dev/null || mkdir -p /home/ga/Documents/exports 2>/dev/null || true

# ---------------------------------------------------------------
# 6. Pre-configure SQL Developer connection
# ---------------------------------------------------------------
echo "Configuring SQL Developer connection..."

SQLDEVELOPER_SYSTEM_DIR=$(find /home/ga/.sqldeveloper -maxdepth 1 -name "system*" -type d 2>/dev/null | head -1)
if [ -n "$SQLDEVELOPER_SYSTEM_DIR" ]; then
    CONN_DIR=$(find "$SQLDEVELOPER_SYSTEM_DIR" -name "o.jdeveloper.db.connection*" -type d 2>/dev/null | head -1)
    if [ -z "$CONN_DIR" ]; then
        CONN_DIR="$SQLDEVELOPER_SYSTEM_DIR/o.jdeveloper.db.connection.24.2.0.284.2209"
        mkdir -p "$CONN_DIR"
    fi

    cat > "$CONN_DIR/connections.json" << 'CONNEOF'
{
  "connections": [
    {
      "name": "Billing Operations",
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
        "ConnName": "Billing Operations",
        "serviceName": "XEPDB1",
        "user": "billing_ops",
        "password": "Billing2024"
      }
    }
  ]
}
CONNEOF
    chown ga:ga "$CONN_DIR/connections.json"
    echo "Connection 'Billing Operations' configured"
fi

# ---------------------------------------------------------------
# 7. Restart SQL Developer so it picks up new connections.json
# ---------------------------------------------------------------
echo "Restarting SQL Developer to load Billing Operations connection..."

# Kill existing SQL Developer processes
pkill -f sqldeveloper 2>/dev/null || true
sleep 3

# Relaunch SQL Developer as user ga
su - ga -c "DISPLAY=:1 setsid /opt/sqldeveloper/sqldeveloper.sh &" 2>/dev/null
sleep 15

# Wait for SQL Developer window
wait_for_window "sql developer\|oracle sql" 30 || true

# Maximize the window
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi
sleep 3

# Try to open the pre-configured connection
open_hr_connection_in_sqldeveloper 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="
echo "Schema: billing_ops / Billing2024"
echo "Tables: customers(30), subscription_plans(6), subscriptions(32), usage_meters(~118),"
echo "        invoices(~178), invoice_line_items(~280), pricing_tiers(15), promotional_credits(8)"
echo "Injected discrepancies: 3 missed, 2 duplicate, 3 wrong_tier, 2 proration, 2 expired_promo, 1 post_cancel = 13 total"
