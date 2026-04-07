#!/usr/bin/env python3
"""Verifier for create_ap_invoice task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

VENDOR_BP_ID = 114       # Tree Farm Inc.
HOLLY_BUSH_ID = 129
OAK_TREE_ID   = 123
EXPECTED_TOTAL_MIN = 200.0
EXPECTED_TOTAL_MAX = 260.0


def verify_create_ap_invoice(traj, env_info, task_info):
    """
    Verify that a vendor invoice was created for Tree Farm Inc. and posted.

    Scoring (100 points):
    - New AP invoice posted (docstatus=CO): 40 points
    - Holly Bush line present with qty >= 5: 25 points
    - Oak Tree line present with qty >= 3: 25 points
    - Grand total in range $200-$260: 10 points

    Pass threshold: 70 points
    An unposted draft invoice with correct lines scores only 60 (fails).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_ap_invoice_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        new_invoices = result.get('new_invoices', [])
        invoice_lines_map = result.get('invoice_lines', {})

        if not new_invoices:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new vendor invoice found for Tree Farm Inc."
            }

        score = 0
        feedback_parts = []

        # Find the best invoice (prefer CO status, then highest total)
        # Accept any new invoice even if draft (partial credit)
        completed = [inv for inv in new_invoices if inv.get('docstatus') == 'CO']
        best_invoice = completed[0] if completed else new_invoices[0]
        inv_id = best_invoice['c_invoice_id']
        docstatus = best_invoice.get('docstatus', '')
        grandtotal = best_invoice.get('grandtotal', 0.0)

        # Criterion 1: Invoice created and posted (CO) — 40 pts
        if docstatus == 'CO':
            score += 40
            feedback_parts.append(f"AP invoice {inv_id} created and posted (CO)")
        else:
            feedback_parts.append(f"AP invoice {inv_id} created but not posted (status={docstatus})")

        # Get lines for the best invoice
        lines = invoice_lines_map.get(str(inv_id), [])

        # Criterion 2: Holly Bush line with qty >= 5
        holly_lines = [l for l in lines if l.get('m_product_id') == HOLLY_BUSH_ID]
        holly_qty = sum(l.get('qty', 0) for l in holly_lines)
        if holly_qty >= 5:
            score += 25
            feedback_parts.append(f"Holly Bush qty={holly_qty} ✓")
        else:
            feedback_parts.append(f"Holly Bush qty={holly_qty} (expected ≥5)")

        # Criterion 3: Oak Tree line with qty >= 3
        oak_lines = [l for l in lines if l.get('m_product_id') == OAK_TREE_ID]
        oak_qty = sum(l.get('qty', 0) for l in oak_lines)
        if oak_qty >= 3:
            score += 25
            feedback_parts.append(f"Oak Tree qty={oak_qty} ✓")
        else:
            feedback_parts.append(f"Oak Tree qty={oak_qty} (expected ≥3)")

        # Criterion 4: Grand total in range — 10 pts
        if EXPECTED_TOTAL_MIN <= grandtotal <= EXPECTED_TOTAL_MAX:
            score += 10
            feedback_parts.append(f"Grand total ${grandtotal:.2f} in expected range ✓")
        else:
            feedback_parts.append(f"Grand total ${grandtotal:.2f} outside expected range ${EXPECTED_TOTAL_MIN}–${EXPECTED_TOTAL_MAX}")

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
