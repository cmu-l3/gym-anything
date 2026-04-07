#!/usr/bin/env python3
"""Verifier for post_period_accruals task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

# c_elementvalue IDs for the required GL accounts
RENT_EXPENSE_ID     = 474   # 61100 Rent Expense
AP_TRADE_ID         = 749   # 21100 Accounts Payable Trade
WAGES_ID            = 772   # 60110 Wages
ACCRUED_PAYROLL_ID  = 602   # 22100 Accrued Payroll

RENT_AMOUNT   = 3200.0
WAGES_AMOUNT  = 8500.0
TOLERANCE     = 50.0


def _has_line(lines, account_id, dr_expected=None, cr_expected=None, tolerance=TOLERANCE):
    """Check if lines contain a specific account with expected DR or CR amount."""
    for line in lines:
        if line.get('account_id') == account_id:
            if dr_expected is not None and abs(line.get('dr', 0) - dr_expected) <= tolerance:
                return True
            if cr_expected is not None and abs(line.get('cr', 0) - cr_expected) <= tolerance:
                return True
    return False


def verify_post_period_accruals(traj, env_info, task_info):
    """
    Verify that both accrual journals were created and posted correctly.

    Scoring (100 points):
    - Rent journal created and posted (CO): 20 points
    - Rent DR line: 61100 $3,200: 15 points
    - Rent CR line: 21100 $3,200: 15 points
    - Wages journal created and posted (CO): 20 points
    - Wages DR line: 60110 $8,500: 15 points
    - Wages CR line: 22100 $8,500: 15 points

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/post_period_accruals_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        new_journals = result.get('new_journals', [])
        journal_lines_map = result.get('journal_lines', {})

        if not new_journals:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new GL journals created"
            }

        score = 0
        feedback_parts = []

        # Collect all lines across all new journals for flexible matching
        # (agent might put both entries in one journal, or two separate ones)
        all_lines = []
        for jnl in new_journals:
            jid = jnl['gl_journal_id']
            all_lines.extend(journal_lines_map.get(str(jid), []))

        # --- Rent accrual: find a journal with Rent-related lines ---
        # Accept: DR 61100 $3200 anywhere + CR 21100 $3200 anywhere (same or different journal)
        rent_journal_posted = any(
            j['docstatus'] == 'CO' for j in new_journals
        )

        has_rent_dr = _has_line(all_lines, RENT_EXPENSE_ID, dr_expected=RENT_AMOUNT)
        has_rent_cr = _has_line(all_lines, AP_TRADE_ID,     cr_expected=RENT_AMOUNT)
        has_wages_dr = _has_line(all_lines, WAGES_ID,           dr_expected=WAGES_AMOUNT)
        has_wages_cr = _has_line(all_lines, ACCRUED_PAYROLL_ID, cr_expected=WAGES_AMOUNT)

        # Score: at least one CO journal exists with rent lines
        rent_journal_co = False
        wages_journal_co = False

        for jnl in new_journals:
            if jnl['docstatus'] != 'CO':
                continue
            jid = jnl['gl_journal_id']
            lines = journal_lines_map.get(str(jid), [])
            if _has_line(lines, RENT_EXPENSE_ID, dr_expected=RENT_AMOUNT) or \
               _has_line(lines, AP_TRADE_ID, cr_expected=RENT_AMOUNT):
                rent_journal_co = True
            if _has_line(lines, WAGES_ID, dr_expected=WAGES_AMOUNT) or \
               _has_line(lines, ACCRUED_PAYROLL_ID, cr_expected=WAGES_AMOUNT):
                wages_journal_co = True

        # Criterion 1: Rent journal posted
        if rent_journal_co:
            score += 20
            feedback_parts.append("Rent accrual journal posted (CO) ✓")
        else:
            feedback_parts.append("Rent accrual journal not found or not posted")

        # Criterion 2: Rent DR line (61100 $3200)
        if has_rent_dr:
            score += 15
            feedback_parts.append("Rent Expense DR $3,200 ✓")
        else:
            feedback_parts.append("Rent Expense (61100) DR $3,200 not found")

        # Criterion 3: Rent CR line (21100 $3200)
        if has_rent_cr:
            score += 15
            feedback_parts.append("AP Trade CR $3,200 ✓")
        else:
            feedback_parts.append("Accounts Payable Trade (21100) CR $3,200 not found")

        # Criterion 4: Wages journal posted
        if wages_journal_co:
            score += 20
            feedback_parts.append("Wages accrual journal posted (CO) ✓")
        else:
            feedback_parts.append("Wages accrual journal not found or not posted")

        # Criterion 5: Wages DR line (60110 $8500)
        if has_wages_dr:
            score += 15
            feedback_parts.append("Wages DR $8,500 ✓")
        else:
            feedback_parts.append("Wages (60110) DR $8,500 not found")

        # Criterion 6: Wages CR line (22100 $8500)
        if has_wages_cr:
            score += 15
            feedback_parts.append("Accrued Payroll CR $8,500 ✓")
        else:
            feedback_parts.append("Accrued Payroll (22100) CR $8,500 not found")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may have failed"}
    except Exception as e:
        logger.exception("Verifier error")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
