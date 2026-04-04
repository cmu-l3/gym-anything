#!/usr/bin/env python3
"""
Verifier for employee_expense_approval task.

Scoring (100 points total):
- Expense report found and approved (state=approve or beyond): 30 points
- Journal entries posted (state=post or beyond): 30 points
- Payment registered to employee (state=done or payment_state=paid): 40 points

Pass threshold: 70 points

Note: Expense report approval → posting → payment is a 3-step sequential workflow.
Each step depends on the previous, so partial scores reflect partial completion.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_employee_expense_approval(traj, env_info, task_info):
    """
    Verify that Sarah Mitchell's expense report was approved, posted, and paid.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        try:
            copy_from_env('/tmp/employee_expense_approval_result.json', temp_file.name)
        except FileNotFoundError:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found — export script may not have run",
            }
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        try:
            with open(temp_file.name) as f:
                result = json.load(f)
        except json.JSONDecodeError as e:
            return {"passed": False, "score": 0, "feedback": f"Result file is not valid JSON: {e}"}
    finally:
        os.unlink(temp_file.name)

    # Handle module-not-installed case
    if result.get('error') == 'hr_expense_not_installed':
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "The Expenses module (hr_expense) is not installed in this Odoo instance. "
                "Task cannot be evaluated. This is a setup issue, not an agent failure."
            ),
        }

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result.get('error')}"}

    metadata = task_info.get('metadata', {})
    employee_name = metadata.get('employee_name', 'Sarah Mitchell')
    report_name = metadata.get('expense_report_name', 'Q1 Client Visit - Chicago')

    score = 0
    feedback_parts = []
    subscores = {}

    sheet_state = result.get('sheet_state', 'unknown')

    # ─── Criterion 1: Expense report approved (30 pts) ────────────────────────
    is_approved = result.get('is_approved', False)

    if is_approved:
        score += 30
        subscores['approved'] = True
        feedback_parts.append(
            f"Expense report approved (state={sheet_state}) (30/30)"
        )
    elif sheet_state == 'submit':
        subscores['approved'] = False
        feedback_parts.append(
            "Expense report still in 'submitted' state — needs manager approval (0/30)"
        )
    elif sheet_state == 'draft':
        subscores['approved'] = False
        feedback_parts.append(
            "Expense report in draft — not even submitted yet (0/30)"
        )
    else:
        subscores['approved'] = False
        feedback_parts.append(
            f"Expense report not approved (state='{sheet_state}') (0/30)"
        )

    # ─── Criterion 2: Journal entries posted (30 pts) ─────────────────────────
    is_posted = result.get('is_posted', False)

    if is_posted:
        score += 30
        subscores['journal_posted'] = True
        feedback_parts.append("Accounting journal entries posted (30/30)")
    elif is_approved:
        subscores['journal_posted'] = False
        feedback_parts.append(
            "Report approved but accounting entries not yet posted — "
            "need to click 'Post Journal Entries' (0/30)"
        )
    else:
        subscores['journal_posted'] = False
        feedback_parts.append(
            "Accounting entries not posted (must approve first) (0/30)"
        )

    # ─── Criterion 3: Payment registered (40 pts) ─────────────────────────────
    is_paid = result.get('is_paid', False)

    if is_paid:
        score += 40
        subscores['payment_registered'] = True
        feedback_parts.append(
            f"Reimbursement payment registered to {employee_name} (40/40)"
        )
    elif is_posted:
        subscores['payment_registered'] = False
        feedback_parts.append(
            "Journal posted but payment not yet registered — "
            "need to click 'Register Payment' to reimburse the employee (0/40)"
        )
    else:
        subscores['payment_registered'] = False
        feedback_parts.append(
            "Payment not registered (complete approval and posting first) (0/40)"
        )

    # ─── Score gate: Payment is a required deliverable ─────────────────────────
    if not is_paid and score >= 70:
        score = 69
        feedback_parts.append("[GATE] Score capped — payment registration is required to pass")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "debug": {
            "employee": employee_name,
            "report": report_name,
            "sheet_state": sheet_state,
            "is_approved": is_approved,
            "is_posted": is_posted,
            "is_paid": is_paid,
        },
    }
