#!/bin/bash
# Export script for Claims Pipeline Reconciliation task
# Queries current DB state across all 5 discrepancy categories,
# checks PL/SQL package, trigger, materialized view, and report file.
# Writes comprehensive JSON to /tmp/task_result.json for the verifier.

echo "=== Exporting Claims Pipeline Reconciliation Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python verification suite
python3 << 'PYEOF'
import oracledb
import json
import os
import sys
from datetime import date

DB_CONFIG = {
    "user": "claims_admin",
    "password": "Claims2024secure",
    "dsn": "localhost:1521/XEPDB1"
}

# Load ground truth
ground_truth = {}
try:
    with open("/tmp/claims_ground_truth.json", "r") as f:
        ground_truth = json.load(f)
except Exception:
    pass

result = {
    # Category 1: Overpayments
    "overpayments_remaining_count": -1,
    "overpayment_details": [],

    # Category 2: Orphaned adjudications
    "orphans_remaining_count": -1,
    "orphan_ids_remaining": [],

    # Category 3: Duplicate payments
    "duplicates_remaining_count": -1,
    "duplicate_claim_ids_remaining": [],

    # Category 4: Eligibility violations
    "eligibility_terminated_remaining": [],
    "eligibility_lapsed_remaining": [],

    # Category 5: Payment mismatches
    "mismatches_remaining_count": -1,
    "mismatch_details": [],

    # PL/SQL Package
    "package_exists": False,
    "package_valid": False,
    "count_discrepancies_result": None,
    "count_discrepancies_error": None,

    # Trigger
    "trigger_exists": False,
    "trigger_blocks_duplicates": None,

    # Materialized View
    "mview_exists": False,
    "mview_row_count": 0,

    # Report File
    "report_exists": False,
    "report_size": 0,
    "report_content_preview": "",

    # Errors
    "errors": []
}

try:
    conn = oracledb.connect(**DB_CONFIG)
    cursor = conn.cursor()

    # ==============================================================
    # CHECK CATEGORY 1: Overpayments
    # Claims where approved_amount > fee_schedule allowed_amount
    # ==============================================================
    try:
        cursor.execute("""
            SELECT a.claim_id, a.approved_amount, f.allowed_amount
            FROM claims_adjudicated a
            JOIN claims_raw c ON a.claim_id = c.claim_id
            JOIN providers p ON c.provider_id = p.provider_id
            JOIN fee_schedule f ON c.procedure_code = f.procedure_code
                               AND p.provider_type = f.provider_type
            WHERE a.approved_amount > f.allowed_amount
            ORDER BY a.claim_id
        """)
        rows = cursor.fetchall()
        result["overpayments_remaining_count"] = len(rows)
        result["overpayment_details"] = [
            {"claim_id": r[0], "approved": float(r[1]), "allowed": float(r[2])}
            for r in rows
        ]
    except Exception as e:
        result["errors"].append(f"Overpayment check: {e}")

    # ==============================================================
    # CHECK CATEGORY 2: Orphaned adjudications
    # Adjudication records with no matching claim in claims_raw
    # ==============================================================
    try:
        cursor.execute("""
            SELECT a.claim_id
            FROM claims_adjudicated a
            WHERE NOT EXISTS (
                SELECT 1 FROM claims_raw c WHERE c.claim_id = a.claim_id
            )
            ORDER BY a.claim_id
        """)
        rows = cursor.fetchall()
        result["orphans_remaining_count"] = len(rows)
        result["orphan_ids_remaining"] = [r[0] for r in rows]
    except Exception as e:
        result["errors"].append(f"Orphan check: {e}")

    # ==============================================================
    # CHECK CATEGORY 3: Duplicate payments
    # claim_ids appearing more than once in payment_authorizations
    # ==============================================================
    try:
        cursor.execute("""
            SELECT claim_id, COUNT(*) as cnt
            FROM payment_authorizations
            GROUP BY claim_id
            HAVING COUNT(*) > 1
            ORDER BY claim_id
        """)
        rows = cursor.fetchall()
        result["duplicates_remaining_count"] = len(rows)
        result["duplicate_claim_ids_remaining"] = [r[0] for r in rows]
    except Exception as e:
        result["errors"].append(f"Duplicate check: {e}")

    # ==============================================================
    # CHECK CATEGORY 4: Eligibility violations
    # Check each designated claim_id for claim_status = 'REJECTED'
    # ==============================================================
    try:
        term_ids = ground_truth.get("terminated_provider_claim_ids", [105, 205, 305, 405])
        for cid in term_ids:
            cursor.execute(
                "SELECT claim_status FROM claims_raw WHERE claim_id = :1", [cid]
            )
            row = cursor.fetchone()
            if row and row[0] != 'REJECTED':
                result["eligibility_terminated_remaining"].append(cid)
    except Exception as e:
        result["errors"].append(f"Terminated provider check: {e}")

    try:
        lapsed_ids = ground_truth.get("lapsed_member_claim_ids", [106, 206, 406])
        for cid in lapsed_ids:
            cursor.execute(
                "SELECT claim_status FROM claims_raw WHERE claim_id = :1", [cid]
            )
            row = cursor.fetchone()
            if row and row[0] != 'REJECTED':
                result["eligibility_lapsed_remaining"].append(cid)
    except Exception as e:
        result["errors"].append(f"Lapsed member check: {e}")

    # ==============================================================
    # CHECK CATEGORY 5: Payment cascade mismatches
    # Check designated claim_ids: payment_amount vs approved_amount
    # ==============================================================
    try:
        mismatch_ids = ground_truth.get("payment_mismatch_claim_ids",
                                        [150, 175, 225, 275, 325])
        mismatch_remaining = []
        for cid in mismatch_ids:
            cursor.execute("""
                SELECT p.payment_amount, a.approved_amount
                FROM payment_authorizations p
                JOIN claims_adjudicated a ON p.claim_id = a.claim_id
                WHERE p.claim_id = :1
            """, [cid])
            row = cursor.fetchone()
            if row and abs(float(row[0]) - float(row[1])) > 0.01:
                mismatch_remaining.append({
                    "claim_id": cid,
                    "payment": float(row[0]),
                    "approved": float(row[1])
                })
        result["mismatches_remaining_count"] = len(mismatch_remaining)
        result["mismatch_details"] = mismatch_remaining
    except Exception as e:
        result["errors"].append(f"Mismatch check: {e}")

    # ==============================================================
    # CHECK PL/SQL PACKAGE
    # ==============================================================
    try:
        cursor.execute("""
            SELECT object_type, status
            FROM user_objects
            WHERE object_name = 'CLAIMS_RECONCILIATION'
            AND object_type IN ('PACKAGE', 'PACKAGE BODY')
            ORDER BY object_type
        """)
        pkg_rows = cursor.fetchall()
        for otype, status in pkg_rows:
            if otype == 'PACKAGE':
                result["package_exists"] = True
            if otype == 'PACKAGE BODY' and status == 'VALID':
                result["package_valid"] = True
    except Exception as e:
        result["errors"].append(f"Package check: {e}")

    # Try to execute COUNT_DISCREPANCIES function
    if result["package_valid"]:
        try:
            count_val = cursor.callfunc(
                "CLAIMS_RECONCILIATION.COUNT_DISCREPANCIES",
                oracledb.NUMBER
            )
            result["count_discrepancies_result"] = int(count_val)
        except Exception as e:
            result["count_discrepancies_error"] = str(e)

    # ==============================================================
    # CHECK TRIGGER
    # ==============================================================
    try:
        cursor.execute("""
            SELECT trigger_name, status
            FROM user_triggers
            WHERE table_name = 'PAYMENT_AUTHORIZATIONS'
        """)
        trig_rows = cursor.fetchall()
        if trig_rows:
            result["trigger_exists"] = True
    except Exception as e:
        result["errors"].append(f"Trigger check: {e}")

    # Functional test: attempt to insert a duplicate payment
    try:
        # Verify claim_id=2 has a payment (it should)
        cursor.execute(
            "SELECT COUNT(*) FROM payment_authorizations WHERE claim_id = 2"
        )
        if cursor.fetchone()[0] > 0:
            try:
                cursor.execute(
                    "INSERT INTO payment_authorizations "
                    "(payment_id, claim_id, payment_amount, payment_date, "
                    "payment_status, check_number) "
                    "VALUES (:1, :2, :3, :4, :5, :6)",
                    [99999, 2, 50.00, date.today(), 'TEST', 'CHK-TEST']
                )
                # Insert succeeded => trigger did NOT block it
                result["trigger_blocks_duplicates"] = False
                conn.rollback()
            except oracledb.DatabaseError:
                # Insert blocked (trigger or constraint)
                result["trigger_blocks_duplicates"] = True
                conn.rollback()
        else:
            result["errors"].append("Trigger test skipped: claim_id=2 has no payment")
    except Exception as e:
        result["errors"].append(f"Trigger functional test: {e}")
        try:
            conn.rollback()
        except Exception:
            pass

    # ==============================================================
    # CHECK MATERIALIZED VIEW
    # ==============================================================
    try:
        cursor.execute("""
            SELECT mview_name FROM user_mviews
            WHERE mview_name = 'RECONCILIATION_DASHBOARD'
        """)
        if cursor.fetchone():
            result["mview_exists"] = True
            try:
                cursor.execute("SELECT COUNT(*) FROM RECONCILIATION_DASHBOARD")
                result["mview_row_count"] = cursor.fetchone()[0]
            except Exception:
                pass
    except Exception as e:
        result["errors"].append(f"MView check: {e}")

    cursor.close()
    conn.close()

except Exception as e:
    result["errors"].append(f"DB connection failed: {e}")

# ==============================================================
# CHECK REPORT FILE
# ==============================================================
report_path = "/home/ga/Desktop/reconciliation_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_size"] = os.path.getsize(report_path)
    try:
        with open(report_path, "r", errors="replace") as f:
            result["report_content_preview"] = f.read(3000)
    except Exception:
        pass

# Write result JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print("Export complete.")
PYEOF

# Validate JSON
python3 -c "import json; json.load(open('/tmp/task_result.json'))" \
    && echo "[OK] Result JSON is valid" \
    || echo "[WARN] Result JSON may be invalid"

chmod 644 /tmp/task_result.json

echo "=== Export Complete ==="
