#!/usr/bin/env python3
"""
Verifier for ar_payment_allocation_aging task.

Checks FIFO payment-to-invoice allocation, open balance view,
aging bucket TVF, and CSV export. Reconciliation is the hard gate.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_ar_payment_allocation_aging(traj, env_info, task_info):
    """
    Verify the AR Payment Allocation Aging task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ar_aging_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        # Try fallback path
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        except Exception as e2:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e2}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    def g(key, default=None):
        return result.get(key, default)

    # ── 1. AR schema exists (3 pts) ─────────────────────────────────────────
    if g('schema_exists'):
        score += 3
        feedback.append("AR schema exists.")
    else:
        feedback.append("AR schema NOT found.")

    # ── 2. PaymentAllocation table exists (5 pts) ───────────────────────────
    if g('alloc_table_exists'):
        score += 5
        feedback.append("PaymentAllocation table exists.")
    else:
        feedback.append("PaymentAllocation table NOT found.")

    # ── 3. PaymentAllocation has required columns (7 pts) ───────────────────
    alloc_cols = str(g('alloc_columns', '')).lower()
    required_cols = ['paymentid', 'salesorderid', 'allocatedamount']
    cols_found = sum(1 for c in required_cols if c in alloc_cols)
    if cols_found == len(required_cols):
        score += 7
        feedback.append("All required allocation columns present.")
    elif cols_found > 0:
        score += int(7 * cols_found / len(required_cols))
        feedback.append(f"Partial allocation columns: {cols_found}/{len(required_cols)}.")
    else:
        feedback.append("PaymentAllocation missing required columns.")

    # ── 4. Stored procedure exists (10 pts) ─────────────────────────────────
    if g('proc_exists'):
        score += 10
        feedback.append("Stored procedure AR.usp_AllocatePayments exists.")
    else:
        feedback.append("Stored procedure AR.usp_AllocatePayments NOT found.")

    # ── 5. RECONCILIATION GATE (15 pts) ─────────────────────────────────────
    reconciliation_passed = False
    try:
        recon_diff = float(g('reconciliation_diff', 999999.99))
        if recon_diff <= 0.01:
            score += 15
            reconciliation_passed = True
            feedback.append(f"Reconciliation PASSED (diff=${recon_diff:.2f}).")
        elif recon_diff <= 1.00:
            score += 10
            reconciliation_passed = True
            feedback.append(f"Reconciliation passed with tolerance (diff=${recon_diff:.2f}).")
        elif recon_diff <= 100.00:
            score += 5
            feedback.append(f"Reconciliation FAILED (diff=${recon_diff:.2f}, too large).")
        else:
            feedback.append(f"Reconciliation FAILED (diff=${recon_diff:.2f}).")
    except (ValueError, TypeError):
        feedback.append("Reconciliation check failed (invalid data).")

    # ── 6. No negative AllocatedAmount (5 pts) ──────────────────────────────
    try:
        neg_count = int(g('negative_alloc_count', -1))
        if neg_count == 0:
            score += 5
            feedback.append("No negative allocations.")
        elif neg_count > 0:
            feedback.append(f"Found {neg_count} negative allocation rows.")
        # neg_count == -1 means check wasn't run
    except (ValueError, TypeError):
        pass

    # ── 7. No invoice over-allocated (10 pts) ───────────────────────────────
    try:
        over_count = int(g('over_alloc_count', -1))
        if over_count == 0:
            score += 10
            feedback.append("No invoices over-allocated.")
        elif over_count > 0:
            feedback.append(f"Found {over_count} over-allocated invoices.")
    except (ValueError, TypeError):
        pass

    # ── 8. Credit balance rows exist (5 pts) ────────────────────────────────
    try:
        credit_rows = int(g('credit_balance_rows', -1))
        if credit_rows > 0:
            score += 5
            feedback.append(f"Credit balance rows present ({credit_rows}).")
        elif credit_rows == 0:
            feedback.append("No credit balance rows (SalesOrderID=-1) found.")
    except (ValueError, TypeError):
        pass

    # ── 9. FIFO ordering spot-check (10 pts) ────────────────────────────────
    fifo_check = str(g('fifo_check', 'unknown'))
    if fifo_check == 'pass':
        score += 10
        feedback.append("FIFO ordering spot-check PASSED.")
    elif fifo_check.startswith('fail'):
        feedback.append(f"FIFO ordering spot-check FAILED ({fifo_check}).")
    else:
        feedback.append("FIFO ordering check not available.")

    # ── 10. View exists + columns (7 pts) ───────────────────────────────────
    if g('view_exists'):
        view_cols = str(g('view_columns', '')).lower()
        has_totaldue = 'totaldue' in view_cols
        has_openbalance = 'openbalance' in view_cols
        if has_totaldue and has_openbalance:
            score += 7
            feedback.append("View vw_InvoiceOpenBalance exists with correct columns.")
        else:
            score += 3
            feedback.append("View exists but missing key columns.")
    else:
        feedback.append("View AR.vw_InvoiceOpenBalance NOT found.")

    # ── 11. View covers all invoices (5 pts) ────────────────────────────────
    try:
        view_rows = int(g('view_row_count', 0))
        total_inv = int(g('total_invoices', 0))
        if total_inv > 0 and abs(view_rows - total_inv) <= max(total_inv * 0.01, 5):
            score += 5
            feedback.append(f"View covers all invoices ({view_rows}/{total_inv}).")
        elif view_rows > 0:
            score += 2
            feedback.append(f"View has {view_rows} rows (expected ~{total_inv}).")
    except (ValueError, TypeError):
        pass

    # ── 12. TVF exists (5 pts) ──────────────────────────────────────────────
    if g('tvf_exists'):
        score += 5
        feedback.append("TVF AR.fn_AgingBuckets exists.")
    else:
        feedback.append("TVF AR.fn_AgingBuckets NOT found.")

    # ── 13. TVF returns data (3 pts) ────────────────────────────────────────
    try:
        tvf_rows = int(g('tvf_row_count', 0))
        if tvf_rows >= 10:
            score += 3
            feedback.append(f"TVF returns {tvf_rows} rows.")
        elif tvf_rows > 0:
            score += 1
            feedback.append(f"TVF returns only {tvf_rows} rows.")
    except (ValueError, TypeError):
        pass

    # ── 14. CSV exists (3 pts) ──────────────────────────────────────────────
    if g('csv_exists'):
        score += 3
        feedback.append("CSV file exists.")
    else:
        feedback.append("CSV file NOT found.")

    # ── 15. CSV created during task session (2 pts) ─────────────────────────
    if g('csv_created_during_task'):
        score += 2
        feedback.append("CSV created during task session.")

    # ── 16. CSV has data with correct header (5 pts) ────────────────────────
    csv_header = str(g('csv_header', '')).lower()
    csv_rows = int(g('csv_rows', 0))
    if csv_rows >= 10 and ('customerid' in csv_header or 'customer' in csv_header):
        score += 5
        feedback.append(f"CSV has {csv_rows} rows with valid header.")
    elif csv_rows > 0:
        score += 2
        feedback.append(f"CSV has {csv_rows} rows (header check inconclusive).")

    # ── Final decision ──────────────────────────────────────────────────────
    # Pass requires score >= 70 AND reconciliation gate
    passed = score >= 70 and reconciliation_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }
