#!/usr/bin/env python3
"""Verifier for configure_customer_credit_and_order task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

AGRITECH_BP_ID      = 200000
EXPECTED_CREDIT_MIN = 14000.0   # Accept $14k–$16k range
EXPECTED_CREDIT_MAX = 16000.0
EXPECTED_PAYTERM_ID = 106       # 2%10 Net 30
AZALEA_BUSH_ID      = 128
HOLLY_BUSH_ID       = 129


def verify_configure_customer_credit_and_order(traj, env_info, task_info):
    """
    Verify Agri-Tech credit/payment terms updated AND a new SO created.

    Scoring (100 points):
    - Credit limit updated to ~$15,000: 25 points
    - Payment terms set to 2%10 Net 30 (id=106): 25 points
    - Azalea Bush qty >= 8 in a new SO: 25 points
    - Holly Bush qty >= 6 in a new SO: 25 points

    Pass threshold: 70 points
    Any 3 of 4 criteria = 75 pts (pass). All 4 = 100 pts.
    An agent who only updates account settings (no SO) scores at most 50 (fails).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_customer_credit_and_order_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []

        def to_float(v, default=0.0):
            try:
                return float(v)
            except (ValueError, TypeError):
                return default

        def to_int(v, default=0):
            try:
                return int(float(v))
            except (ValueError, TypeError):
                return default

        # Criterion 1: Credit limit updated
        credit = to_float(result.get('current_credit_limit', '0'))
        init_credit = to_float(result.get('initial_credit_limit', '5000'))
        if EXPECTED_CREDIT_MIN <= credit <= EXPECTED_CREDIT_MAX and credit != init_credit:
            score += 25
            feedback_parts.append(f"Credit limit ${credit:.0f} ✓")
        else:
            feedback_parts.append(
                f"Credit limit ${credit:.0f} incorrect (expected ~$15,000, initial was ${init_credit:.0f})"
            )

        # Criterion 2: Payment terms updated to 2%10 Net 30
        payterm = to_int(result.get('current_payterm_id', '0'))
        init_payterm = to_int(result.get('initial_payterm_id', '105'))
        if payterm == EXPECTED_PAYTERM_ID and payterm != init_payterm:
            score += 25
            feedback_parts.append("Payment terms set to 2%10 Net 30 ✓")
        else:
            feedback_parts.append(
                f"Payment terms id={payterm} incorrect (expected id=106 for '2%10 Net 30', initial={init_payterm})"
            )

        # Find new sales orders for Agri-Tech — search across all new SOs for product lines
        new_orders = result.get('new_sales_orders', [])
        order_lines_map = result.get('order_lines', {})

        # Aggregate all lines across all new SOs
        all_lines = []
        for so in new_orders:
            all_lines.extend(order_lines_map.get(str(so['c_order_id']), []))

        if not new_orders:
            feedback_parts.append("No new sales order created for Agri-Tech (Azalea Bush and Holly Bush not placed)")
        else:
            feedback_parts.append(f"New SO(s) created for Agri-Tech ({len(new_orders)} order(s))")

        # Criterion 3: Azalea Bush qty >= 8 in new SO(s)
        azalea_qty = sum(l.get('qty', 0) for l in all_lines if l.get('m_product_id') == AZALEA_BUSH_ID)
        if azalea_qty >= 8:
            score += 25
            feedback_parts.append(f"Azalea Bush qty={azalea_qty} ✓")
        else:
            feedback_parts.append(f"Azalea Bush qty={azalea_qty} (expected ≥8 in new SO)")

        # Criterion 4: Holly Bush qty >= 6 in new SO(s)
        holly_qty = sum(l.get('qty', 0) for l in all_lines if l.get('m_product_id') == HOLLY_BUSH_ID)
        if holly_qty >= 6:
            score += 25
            feedback_parts.append(f"Holly Bush qty={holly_qty} ✓")
        else:
            feedback_parts.append(f"Holly Bush qty={holly_qty} (expected ≥6 in new SO)")

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
