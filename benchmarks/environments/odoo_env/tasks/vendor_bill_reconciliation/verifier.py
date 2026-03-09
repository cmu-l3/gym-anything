#!/usr/bin/env python3
"""
Verifier for vendor_bill_reconciliation task.

Scoring (100 points total):
- Correct vendor targeted (gate: score=0 if wrong vendor)
- Bill amount corrected to match PO: 30 points
- Bill posted/validated: 20 points
- Payment registered (paid or in_payment): 35 points
- Bill amount within 5% tolerance of PO amount: 15 bonus points (included in amount check)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_vendor_bill_reconciliation(traj, env_info, task_info):
    """Verify that the vendor bill was corrected to match the PO and payment was registered."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result file from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        try:
            copy_from_env('/tmp/vendor_bill_reconciliation_result.json', temp_file.name)
        except FileNotFoundError:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found — export script may not have run or task setup failed",
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

    if result.get('error') and not result.get('vendor_id'):
        return {"passed": False, "score": 0, "feedback": f"Setup error: {result.get('error')}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # ─── CRITICAL: Wrong-vendor gate ────────────────────────────────────────────
    # The vendor targeted must be the one we set up. If the agent acted on a
    # different vendor's bills, that's a wrong-target failure.
    bill_partner_id = result.get('bill_partner_id')
    expected_vendor_id = result.get('vendor_id')
    if bill_partner_id and expected_vendor_id and bill_partner_id != expected_vendor_id:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"CRITICAL: Wrong vendor targeted! "
                f"Expected vendor_id={expected_vendor_id} ({result.get('vendor_name', 'unknown')}), "
                f"but bill belongs to partner_id={bill_partner_id}."
            ),
        }

    expected_amount = result.get('expected_amount', 0)
    inflated_amount = result.get('inflated_amount', 0)

    # ─── Criterion 1: Bill amount corrected (30 pts) ─────────────────────────
    bill_amount = result.get('bill_amount') or 0
    if expected_amount > 0:
        amount_diff_pct = abs(bill_amount - expected_amount) / expected_amount
        if amount_diff_pct < 0.05:
            score += 30
            subscores['amount_corrected'] = True
            feedback_parts.append(
                f"Bill amount correctly adjusted to ${bill_amount:.2f} "
                f"(expected ${expected_amount:.2f}) (30/30)"
            )
        elif amount_diff_pct < 0.15:
            # Partial credit for close-ish correction
            score += 10
            subscores['amount_corrected'] = 'partial'
            feedback_parts.append(
                f"Bill amount ${bill_amount:.2f} is close to expected ${expected_amount:.2f} "
                f"but not within 5% tolerance (10/30)"
            )
        else:
            subscores['amount_corrected'] = False
            original_inflated = inflated_amount or 0
            if abs(bill_amount - original_inflated) < 1:
                feedback_parts.append(
                    f"Bill amount unchanged at ${bill_amount:.2f} (still overcharged vs PO ${expected_amount:.2f}) (0/30)"
                )
            else:
                feedback_parts.append(
                    f"Bill amount ${bill_amount:.2f} doesn't match PO amount ${expected_amount:.2f} (0/30)"
                )
    else:
        subscores['amount_corrected'] = False
        feedback_parts.append("Could not verify bill amount (expected_amount missing) (0/30)")

    # ─── Criterion 2: Bill posted/validated (20 pts) ─────────────────────────
    bill_state = result.get('bill_state', 'unknown')
    if bill_state == 'posted':
        score += 20
        subscores['bill_posted'] = True
        feedback_parts.append("Bill is posted/validated (20/20)")
    elif bill_state == 'draft':
        subscores['bill_posted'] = False
        feedback_parts.append("Bill still in draft — not posted/validated (0/20)")
    elif bill_state == 'cancel':
        subscores['bill_posted'] = False
        feedback_parts.append("Bill was cancelled — should have been corrected and posted (0/20)")
    else:
        subscores['bill_posted'] = False
        feedback_parts.append(f"Bill state is '{bill_state}' — expected 'posted' (0/20)")

    # ─── Criterion 3: Payment registered (35 pts) ────────────────────────────
    payment_state = result.get('bill_payment_state', 'not_paid')
    if payment_state in ['paid', 'in_payment']:
        score += 35
        subscores['payment_registered'] = True
        feedback_parts.append(f"Payment registered (payment_state={payment_state}) (35/35)")
    elif payment_state == 'partial':
        score += 15
        subscores['payment_registered'] = 'partial'
        feedback_parts.append("Partial payment registered — full payment required (15/35)")
    else:
        subscores['payment_registered'] = False
        feedback_parts.append(f"No payment registered (payment_state={payment_state}) (0/35)")

    # ─── Bonus: Check via broader search (any corrected+paid bill for this vendor) ─
    # If the agent paid a different (but corrected) bill for the same vendor, give credit
    if not subscores.get('payment_registered') and result.get('any_bill_correct_and_paid'):
        score += 35
        subscores['payment_registered'] = 'other_bill'
        feedback_parts.append(
            "A vendor bill with correct amount was found and paid (possibly a different bill) (35/35 awarded)"
        )

    # ─── Determine pass/fail ─────────────────────────────────────────────────
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "debug": {
            "bill_amount": bill_amount,
            "expected_amount": expected_amount,
            "bill_state": bill_state,
            "payment_state": payment_state,
        },
    }
