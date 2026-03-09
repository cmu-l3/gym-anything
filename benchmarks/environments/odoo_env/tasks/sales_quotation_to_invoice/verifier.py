#!/usr/bin/env python3
"""
Verifier for sales_quotation_to_invoice task.

Scoring (100 points total):
- Sales order confirmed (state=sale/done): 15 points
- Correct products on order: 20 points
- Payment terms set to 30 days: 10 points
- Internal note with 'priority': 10 points
- Invoice posted (validated): 20 points
- Invoice paid (full payment registered): 25 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_sales_quotation_to_invoice(traj, env_info, task_info):
    """Verify the full sales quotation → invoice → payment workflow."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        try:
            copy_from_env('/tmp/sales_quotation_to_invoice_result.json', temp_file.name)
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

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result.get('error')}"}

    metadata = task_info.get('metadata', {})
    customer_name = metadata.get('customer_name', 'Meridian Pacific Group')

    score = 0
    feedback_parts = []
    subscores = {}

    # ─── CRITICAL: Must have found a sales order ──────────────────────────────
    if not result.get('order_found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No sales order found for customer '{customer_name}' — order was never created",
        }

    # ─── Criterion 1: Order confirmed (15 pts) ────────────────────────────────
    if result.get('order_confirmed'):
        score += 15
        subscores['order_confirmed'] = True
        feedback_parts.append("Sales order confirmed (15/15)")
    else:
        subscores['order_confirmed'] = False
        feedback_parts.append("Sales order not confirmed — still in draft (0/15)")

    # ─── Criterion 2: Correct products on order (20 pts) ─────────────────────
    if result.get('order_has_correct_products'):
        score += 20
        subscores['correct_products'] = True
        feedback_parts.append("Both required products found on order (20/20)")
    else:
        # Partial: at least order exists and has some products
        if result.get('order_found'):
            score += 5
            subscores['correct_products'] = 'partial'
            feedback_parts.append(
                "Order exists but missing one or both required products "
                "(Standing Desk Pro, Executive High-Back Chair) (5/20)"
            )
        else:
            subscores['correct_products'] = False
            feedback_parts.append("Required products not found on order (0/20)")

    # ─── Criterion 3: Payment terms (10 pts) ─────────────────────────────────
    if result.get('has_payment_terms_30'):
        score += 10
        subscores['payment_terms'] = True
        feedback_parts.append("Payment terms set to 30 days (10/10)")
    else:
        subscores['payment_terms'] = False
        feedback_parts.append("Payment terms not set to 30 days (0/10)")

    # ─── Criterion 4: Internal note (10 pts) ─────────────────────────────────
    if result.get('has_priority_note'):
        score += 10
        subscores['note_added'] = True
        feedback_parts.append("Priority note added to order (10/10)")
    else:
        subscores['note_added'] = False
        feedback_parts.append("Note 'Priority order — expedite shipping' not found on order (0/10)")

    # ─── Criterion 5: Invoice posted (20 pts) ────────────────────────────────
    if result.get('invoice_posted'):
        score += 20
        subscores['invoice_posted'] = True
        feedback_parts.append("Invoice created and posted (20/20)")
    else:
        subscores['invoice_posted'] = False
        feedback_parts.append("Invoice not created or not posted/validated (0/20)")

    # ─── Criterion 6: Invoice paid (25 pts) ──────────────────────────────────
    if result.get('invoice_paid'):
        score += 25
        subscores['invoice_paid'] = True
        feedback_parts.append("Full payment registered for invoice (25/25)")
    else:
        subscores['invoice_paid'] = False
        feedback_parts.append("Payment not registered for invoice (0/25)")

    # ─── GATE: Invoice must be paid to pass (even if all else is correct) ─────
    if not result.get('invoice_paid') and score >= 70:
        score = 69
        feedback_parts.append("[GATE] Score capped: invoice payment is required to pass")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores,
        "debug": {
            "customer": customer_name,
            "order_id": result.get('order_id'),
            "order_amount": result.get('order_amount'),
            "expected_amount": result.get('expected_amount'),
        },
    }
