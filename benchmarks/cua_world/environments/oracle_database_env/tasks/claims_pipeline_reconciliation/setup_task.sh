#!/bin/bash
# Setup script for Claims Pipeline Reconciliation task
# Creates CLAIMS_ADMIN schema with 6 tables, seeds ~1700 rows of realistic
# healthcare claims data, and plants 25 discrepancies across 5 categories.

set -e

echo "=== Setting up Claims Pipeline Reconciliation Task ==="

source /workspace/scripts/task_utils.sh

# ---------------------------------------------------------------
# [1/6] Pre-flight: Verify Oracle container is running
# ---------------------------------------------------------------
echo "[1/6] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container ($ORACLE_CONTAINER) not running!"
    exit 1
fi

# ---------------------------------------------------------------
# [2/6] Verify DB connectivity via HR schema
# ---------------------------------------------------------------
echo "[2/6] Verifying database connectivity..."
CONN_OK=0
for attempt in 1 2 3; do
    CONN_TEST=$(oracle_query_raw "SELECT COUNT(*) FROM employees;" "hr" 2>/dev/null | tr -d ' ')
    if [[ "$CONN_TEST" =~ ^[0-9]+$ ]] && [ "$CONN_TEST" -ge 100 ]; then
        echo "  Database ready (HR has $CONN_TEST employees)"
        CONN_OK=1
        break
    fi
    echo "  Attempt $attempt failed, waiting 10s..."
    sleep 10
done
if [ "$CONN_OK" -eq 0 ]; then
    echo "ERROR: Cannot connect to database after 3 attempts"
    exit 1
fi

# ---------------------------------------------------------------
# [3/6] Create CLAIMS_ADMIN user (as SYSTEM)
# ---------------------------------------------------------------
echo "[3/6] Creating CLAIMS_ADMIN schema..."
oracle_query "
BEGIN
    EXECUTE IMMEDIATE 'DROP USER claims_admin CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

CREATE USER claims_admin IDENTIFIED BY Claims2024secure;
GRANT CONNECT, RESOURCE TO claims_admin;
GRANT CREATE MATERIALIZED VIEW TO claims_admin;
GRANT CREATE VIEW TO claims_admin;
GRANT UNLIMITED TABLESPACE TO claims_admin;
" "system" > /dev/null 2>&1

# Verify user was created
USER_EXISTS=$(oracle_query_raw "SELECT COUNT(*) FROM all_users WHERE username = 'CLAIMS_ADMIN';" "system" | tr -d ' ')
if [ "${USER_EXISTS:-0}" -eq 0 ]; then
    echo "ERROR: Failed to create CLAIMS_ADMIN user"
    exit 1
fi
echo "  CLAIMS_ADMIN user created successfully"

# ---------------------------------------------------------------
# [4/6] Seed data via Python (tables + data + discrepancies)
# ---------------------------------------------------------------
echo "[4/6] Seeding claims data..."

python3 << 'PYEOF'
import oracledb
import json
import os
import sys
from datetime import date, timedelta

try:
    conn = oracledb.connect(
        user="claims_admin",
        password="Claims2024secure",
        dsn="localhost:1521/XEPDB1"
    )
    cursor = conn.cursor()

    # ==========================================================
    # CREATE TABLES
    # ==========================================================
    cursor.execute("""
        CREATE TABLE providers (
            provider_id    NUMBER PRIMARY KEY,
            npi            VARCHAR2(10) NOT NULL,
            provider_name  VARCHAR2(100) NOT NULL,
            provider_type  VARCHAR2(20) NOT NULL,
            active_status  CHAR(1) DEFAULT 'Y' NOT NULL,
            effective_date DATE NOT NULL,
            termination_date DATE
        )
    """)

    cursor.execute("""
        CREATE TABLE members (
            member_id      NUMBER PRIMARY KEY,
            member_name    VARCHAR2(100) NOT NULL,
            date_of_birth  DATE NOT NULL,
            plan_type      VARCHAR2(10) NOT NULL,
            coverage_start DATE NOT NULL,
            coverage_end   DATE
        )
    """)

    cursor.execute("""
        CREATE TABLE fee_schedule (
            fee_id          NUMBER PRIMARY KEY,
            procedure_code  VARCHAR2(10) NOT NULL,
            provider_type   VARCHAR2(20) NOT NULL,
            allowed_amount  NUMBER(10,2) NOT NULL,
            effective_date  DATE NOT NULL,
            CONSTRAINT uq_fee_proc_type UNIQUE (procedure_code, provider_type)
        )
    """)

    cursor.execute("""
        CREATE TABLE claims_raw (
            claim_id        NUMBER PRIMARY KEY,
            member_id       NUMBER NOT NULL REFERENCES members(member_id),
            provider_id     NUMBER NOT NULL REFERENCES providers(provider_id),
            service_date    DATE NOT NULL,
            procedure_code  VARCHAR2(10) NOT NULL,
            diagnosis_code  VARCHAR2(10),
            billed_amount   NUMBER(10,2) NOT NULL,
            claim_status    VARCHAR2(20) DEFAULT 'SUBMITTED' NOT NULL,
            submission_date DATE NOT NULL
        )
    """)

    cursor.execute("""
        CREATE TABLE claims_adjudicated (
            adjudication_id  NUMBER PRIMARY KEY,
            claim_id         NUMBER NOT NULL,
            approved_amount  NUMBER(10,2) NOT NULL,
            copay_amount     NUMBER(10,2),
            denial_code      VARCHAR2(10),
            adjudication_date DATE NOT NULL,
            adjudicator_id   NUMBER
        )
    """)

    cursor.execute("""
        CREATE TABLE payment_authorizations (
            payment_id      NUMBER PRIMARY KEY,
            claim_id        NUMBER NOT NULL,
            payment_amount  NUMBER(10,2) NOT NULL,
            payment_date    DATE NOT NULL,
            payment_status  VARCHAR2(20) DEFAULT 'AUTHORIZED' NOT NULL,
            check_number    VARCHAR2(20)
        )
    """)

    conn.commit()
    print("  Tables created.")

    # ==========================================================
    # CONSTANTS
    # ==========================================================
    cpt_codes = [
        '99213', '99214', '99215', '99201', '99202',
        '99203', '99211', '99212', '36415', '80053',
        '80061', '71046', '71047', '99281', '99282',
        '99283', '99284', '99285', '93000', '90471'
    ]

    ptypes = ['HOSPITAL', 'CLINIC', 'SPECIALIST', 'LAB', 'URGENT_CARE']

    icd_codes = [
        'J06.9', 'M54.5', 'E11.9', 'I10',   'J44.1',
        'K21.0', 'F32.9', 'N39.0', 'R10.9',  'S93.40',
        'L03.11', 'J18.9', 'K80.20', 'N18.6', 'D64.9',
        'G43.90', 'R50.9', 'I25.10', 'Z23',   'R05.9'
    ]

    base_amounts = {
        '99213': 130.00, '99214': 195.00, '99215': 265.00,
        '99201':  75.00, '99202': 115.00, '99203': 170.00,
        '99211':  45.00, '99212':  85.00, '36415':  12.00,
        '80053':  25.00, '80061':  35.00, '71046':  60.00,
        '71047':  80.00, '99281':  90.00, '99282': 155.00,
        '99283': 250.00, '99284': 380.00, '99285': 490.00,
        '93000':  35.00, '90471':  28.00
    }

    multipliers = {
        'HOSPITAL': 1.3, 'CLINIC': 1.0, 'SPECIALIST': 1.2,
        'LAB': 0.8, 'URGENT_CARE': 1.1
    }

    first_names = [
        'James', 'Mary', 'Robert', 'Patricia', 'John',
        'Jennifer', 'Michael', 'Linda', 'David', 'Elizabeth',
        'William', 'Barbara', 'Richard', 'Susan', 'Joseph',
        'Jessica', 'Thomas', 'Sarah', 'Christopher', 'Karen'
    ]

    last_names = [
        'Smith', 'Johnson', 'Williams', 'Brown', 'Jones',
        'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez'
    ]

    city_prefixes = [
        'Metro', 'Valley', 'Lakeside', 'Highland', 'Riverside',
        'Bayshore', 'Cedar', 'Pacific', 'Northern', 'Southern'
    ]

    type_suffixes = {
        'HOSPITAL': 'General Hospital',
        'CLINIC': 'Family Clinic',
        'SPECIALIST': 'Specialty Group',
        'LAB': 'Diagnostics Lab',
        'URGENT_CARE': 'Urgent Care Center'
    }

    plan_types = ['HMO', 'PPO', 'EPO']
    base_date = date(2024, 7, 1)

    # Pre-compute fee schedule lookup
    fee_lookup = {}
    for proc in cpt_codes:
        for pt in ptypes:
            fee_lookup[(proc, pt)] = round(base_amounts[proc] * multipliers[pt], 2)

    # ==========================================================
    # INSERT PROVIDERS (50)
    # Providers 46-50 are terminated (termination_date = 2024-06-30)
    # ==========================================================
    provider_data = []
    for i in range(1, 51):
        ptype = ptypes[(i - 1) % 5]
        city = city_prefixes[(i - 1) // 5]
        name = f"{city} {type_suffixes[ptype]}"
        npi = f'{1000000000 + i}'
        active = 'N' if i >= 46 else 'Y'
        eff_date = date(2015, 1, 1)
        term_date = date(2024, 6, 30) if i >= 46 else None
        provider_data.append((i, npi, name, ptype, active, eff_date, term_date))

    cursor.executemany(
        "INSERT INTO providers VALUES (:1,:2,:3,:4,:5,:6,:7)",
        provider_data
    )
    print(f"  Providers: {len(provider_data)} rows")

    # ==========================================================
    # INSERT MEMBERS (200)
    # Members 191-200 have lapsed coverage (coverage_end = 2024-06-30)
    # ==========================================================
    member_data = []
    for i in range(1, 201):
        fn = first_names[(i - 1) % 20]
        ln = last_names[(i - 1) // 20]
        name = f"{fn} {ln}"
        dob = date(1955, 1, 1) + timedelta(days=(i - 1) * 127)
        plan = plan_types[(i - 1) % 3]
        cov_start = date(2022, 1, 1)
        cov_end = date(2024, 6, 30) if i >= 191 else None
        member_data.append((i, name, dob, plan, cov_start, cov_end))

    cursor.executemany(
        "INSERT INTO members VALUES (:1,:2,:3,:4,:5,:6)",
        member_data
    )
    print(f"  Members: {len(member_data)} rows")

    # ==========================================================
    # INSERT FEE SCHEDULE (100 = 20 procedures x 5 provider types)
    # ==========================================================
    fee_data = []
    fee_id = 1
    for proc in cpt_codes:
        for pt in ptypes:
            allowed = fee_lookup[(proc, pt)]
            fee_data.append((fee_id, proc, pt, allowed, date(2024, 1, 1)))
            fee_id += 1

    cursor.executemany(
        "INSERT INTO fee_schedule VALUES (:1,:2,:3,:4,:5)",
        fee_data
    )
    print(f"  Fee Schedule: {len(fee_data)} rows")

    # ==========================================================
    # INSERT CLAIMS_RAW (500)
    # All initially assigned to active providers/members only.
    # Eligibility violations are planted via UPDATE below.
    # ==========================================================
    claim_data = []
    for i in range(1, 501):
        member_id = ((i - 1) % 190) + 1      # active members 1-190
        provider_id = ((i - 1) % 45) + 1     # active providers 1-45
        proc = cpt_codes[(i - 1) % 20]
        diag = icd_codes[(i - 1) % 20]
        ptype = ptypes[(provider_id - 1) % 5]
        allowed = fee_lookup[(proc, ptype)]
        billed = round(allowed * 1.15, 2)
        svc_date = base_date + timedelta(days=((i - 1) * 37) % 184)
        sub_date = svc_date + timedelta(days=3)
        status = 'ADJUDICATED'
        claim_data.append((i, member_id, provider_id, svc_date, proc, diag,
                           billed, status, sub_date))

    cursor.executemany(
        "INSERT INTO claims_raw VALUES (:1,:2,:3,:4,:5,:6,:7,:8,:9)",
        claim_data
    )
    print(f"  Claims Raw: {len(claim_data)} rows")

    # ==========================================================
    # INSERT CLAIMS_ADJUDICATED (446 legitimate for claims 1-446)
    # Orphaned adjudications and overpayments planted below.
    # ==========================================================
    adj_data = []
    for i in range(1, 447):
        claim_id = i
        provider_id = ((claim_id - 1) % 45) + 1
        ptype = ptypes[(provider_id - 1) % 5]
        proc = cpt_codes[(claim_id - 1) % 20]
        allowed = fee_lookup[(proc, ptype)]
        approved = allowed
        copay = round(allowed * 0.2, 2)
        svc_date = base_date + timedelta(days=((claim_id - 1) * 37) % 184)
        adj_date = svc_date + timedelta(days=14)
        adjudicator = ((i - 1) % 10) + 1001
        adj_data.append((i, claim_id, approved, copay, None, adj_date, adjudicator))

    cursor.executemany(
        "INSERT INTO claims_adjudicated VALUES (:1,:2,:3,:4,:5,:6,:7)",
        adj_data
    )
    print(f"  Adjudications (legitimate): {len(adj_data)} rows")

    # ==========================================================
    # INSERT PAYMENT_AUTHORIZATIONS (396 legitimate for claims 1-396)
    # Duplicates and mismatches planted below.
    # ==========================================================
    pay_data = []
    for i in range(1, 397):
        claim_id = i
        provider_id = ((claim_id - 1) % 45) + 1
        ptype = ptypes[(provider_id - 1) % 5]
        proc = cpt_codes[(claim_id - 1) % 20]
        allowed = fee_lookup[(proc, ptype)]
        payment_amt = allowed  # matches approved_amount
        svc_date = base_date + timedelta(days=((claim_id - 1) * 37) % 184)
        pay_date = svc_date + timedelta(days=21)
        check_num = f'CHK-{1000000 + i}'
        pay_data.append((i, claim_id, payment_amt, pay_date, 'AUTHORIZED', check_num))

    cursor.executemany(
        "INSERT INTO payment_authorizations VALUES (:1,:2,:3,:4,:5,:6)",
        pay_data
    )
    print(f"  Payments (legitimate): {len(pay_data)} rows")

    conn.commit()

    # ==========================================================
    # PLANT DISCREPANCIES
    # ==========================================================
    print("  Planting discrepancies...")

    # --- Category 1: Overpayments (5) ---
    # Claims 397-402 (excl 400) have adjudications but no payments.
    # Set approved_amount to 2x the correct fee schedule amount.
    overpayment_ids = [397, 398, 399, 401, 402]
    for cid in overpayment_ids:
        cursor.execute(
            "UPDATE claims_adjudicated SET approved_amount = approved_amount * 2 "
            "WHERE claim_id = :1",
            [cid]
        )
    print(f"    Overpayments: {len(overpayment_ids)} claims")

    # --- Category 2: Orphaned adjudications (4) ---
    # Insert adjudication records whose claim_ids don't exist in claims_raw.
    orphan_claim_ids = [9901, 9902, 9903, 9904]
    for idx, cid in enumerate(orphan_claim_ids):
        cursor.execute(
            "INSERT INTO claims_adjudicated VALUES (:1,:2,:3,:4,:5,:6,:7)",
            [447 + idx, cid, 150.00, 30.00, None, date(2024, 11, 15), 1005]
        )
    print(f"    Orphaned adjudications: {len(orphan_claim_ids)} records")

    # --- Category 3: Duplicate payments (4) ---
    # Insert second payment rows for claims that already have payments.
    dup_claim_ids = [200, 250, 300, 350]
    for idx, cid in enumerate(dup_claim_ids):
        cursor.execute(
            "SELECT payment_amount FROM payment_authorizations WHERE claim_id = :1",
            [cid]
        )
        amt = cursor.fetchone()[0]
        cursor.execute(
            "INSERT INTO payment_authorizations VALUES (:1,:2,:3,:4,:5,:6)",
            [397 + idx, cid, amt, date(2024, 12, 1), 'AUTHORIZED',
             f'CHK-DUP-{idx + 1}']
        )
    print(f"    Duplicate payments: {len(dup_claim_ids)} claims")

    # --- Category 4: Eligibility violations (7) ---
    # Point 4 claims at terminated providers (46-49).
    # Claims chosen so provider_type matches (avoids false overpayment).
    term_provider_claims = {101: 46, 102: 47, 103: 48, 104: 49}
    for cid, pid in term_provider_claims.items():
        cursor.execute(
            "UPDATE claims_raw SET provider_id = :1 WHERE claim_id = :2",
            [pid, cid]
        )

    # Point 3 claims at lapsed members (191-193)
    lapsed_member_claims = {106: 191, 206: 192, 406: 193}
    for cid, mid in lapsed_member_claims.items():
        cursor.execute(
            "UPDATE claims_raw SET member_id = :1 WHERE claim_id = :2",
            [mid, cid]
        )
    elig_count = len(term_provider_claims) + len(lapsed_member_claims)
    print(f"    Eligibility violations: {elig_count} claims")

    # --- Category 5: Payment cascade mismatches (5) ---
    # Set payment_amount to 70% of approved_amount (a 30% underpayment).
    mismatch_ids = [150, 175, 225, 275, 325]
    for cid in mismatch_ids:
        cursor.execute(
            "UPDATE payment_authorizations "
            "SET payment_amount = ROUND(payment_amount * 0.7, 2) "
            "WHERE claim_id = :1",
            [cid]
        )
    print(f"    Payment mismatches: {len(mismatch_ids)} claims")

    conn.commit()

    # ==========================================================
    # RECORD GROUND TRUTH (hidden from agent)
    # ==========================================================
    ground_truth = {
        "overpayment_claim_ids": overpayment_ids,
        "orphaned_adjudication_claim_ids": orphan_claim_ids,
        "duplicate_payment_claim_ids": dup_claim_ids,
        "terminated_provider_claim_ids": list(term_provider_claims.keys()),
        "lapsed_member_claim_ids": list(lapsed_member_claims.keys()),
        "payment_mismatch_claim_ids": mismatch_ids,
        "total_discrepancies": 25
    }

    with open("/tmp/claims_ground_truth.json", "w") as f:
        json.dump(ground_truth, f, indent=2)
    os.chmod("/tmp/claims_ground_truth.json", 0o600)

    # Print final table counts
    for tbl in ['providers', 'members', 'fee_schedule',
                'claims_raw', 'claims_adjudicated', 'payment_authorizations']:
        cursor.execute(f"SELECT COUNT(*) FROM {tbl}")
        print(f"  Final count {tbl}: {cursor.fetchone()[0]}")

    conn.close()
    print("  Data seeding complete.")

except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc(file=sys.stderr)
    sys.exit(1)
PYEOF

# ---------------------------------------------------------------
# [5/6] Clean prior output files and record timestamp
# ---------------------------------------------------------------
echo "[5/6] Preparing workspace..."
rm -f /home/ga/Desktop/reconciliation_report.txt
date +%s > /tmp/task_start_timestamp
chmod 600 /tmp/task_start_timestamp

# ---------------------------------------------------------------
# [6/6] Launch DBeaver and take initial screenshot
# ---------------------------------------------------------------
echo "[6/6] Launching DBeaver..."
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "dbeaver"; then
    su - ga -c "DISPLAY=:1 /snap/bin/dbeaver-ce &" > /dev/null 2>&1 || \
    su - ga -c "DISPLAY=:1 dbeaver-ce &" > /dev/null 2>&1 || true
    sleep 6
fi

take_screenshot /tmp/task_initial.png

echo "=== Claims Pipeline Reconciliation Setup Complete ==="
