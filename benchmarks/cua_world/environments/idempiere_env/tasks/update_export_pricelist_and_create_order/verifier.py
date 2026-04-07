#!/usr/bin/env python3
"""Verifier for update_export_pricelist_and_create_order task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PATIOFUN_BP_ID   = 121
PATIO_CHAIR_ID   = 133
PATIO_TABLE_ID   = 134
PATIO_SCREEN_ID  = 135

EXPECTED_CHAIR_PRICE  = 32.00
EXPECTED_TABLE_PRICE  = 65.00
EXPECTED_SCREEN_PRICE = 21.50


def verify_update_export_pricelist_and_create_order(traj, env_info, task_info):
    """
    Verify export prices updated AND an export SO created for Patio Fun Inc.

    Scoring (100 points):
    - Patio Chair export price = $32.00: 12 points
    - Patio Table export price = $65.00: 12 points
    - Patio Sun Screen export price = $21.50: 11 points
    - New SO created for Patio Fun Inc.: 15 points
    - Patio Chair qty >= 20: 17 points
    - Patio Table qty >= 8: 17 points
    - Patio Sun Screen qty >= 12: 16 points

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(
                "/tmp/update_export_pricelist_and_create_order_result.json",
                temp_file.name
            )
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []

        def price_ok(current_str, expected, tolerance=0.10):
            try:
                return abs(float(current_str) - expected) <= tolerance
            except (ValueError, TypeError):
                return False

        def price_changed(current_str, initial_str):
            try:
                return abs(float(current_str) - float(initial_str)) > 0.001
            except (ValueError, TypeError):
                return False

        # Criterion 1: Patio Chair export price = $32.00
        chair = result.get('current_chair_price', '0')
        init_chair = result.get('initial_chair_price', '0')
        if price_ok(chair, EXPECTED_CHAIR_PRICE) and price_changed(chair, init_chair):
            score += 12
            feedback_parts.append(f"Patio Chair export price ${chair} ✓")
        else:
            feedback_parts.append(
                f"Patio Chair export price ${chair} incorrect (expected $32.00, was ${init_chair})"
            )

        # Criterion 2: Patio Table export price = $65.00
        table = result.get('current_table_price', '0')
        init_table = result.get('initial_table_price', '0')
        if price_ok(table, EXPECTED_TABLE_PRICE) and price_changed(table, init_table):
            score += 12
            feedback_parts.append(f"Patio Table export price ${table} ✓")
        else:
            feedback_parts.append(
                f"Patio Table export price ${table} incorrect (expected $65.00, was ${init_table})"
            )

        # Criterion 3: Patio Sun Screen export price = $21.50
        screen = result.get('current_screen_price', '0')
        init_screen = result.get('initial_screen_price', '0')
        if price_ok(screen, EXPECTED_SCREEN_PRICE) and price_changed(screen, init_screen):
            score += 11
            feedback_parts.append(f"Patio Sun Screen export price ${screen} ✓")
        else:
            feedback_parts.append(
                f"Patio Sun Screen export price ${screen} incorrect (expected $21.50, was ${init_screen})"
            )

        # Sales order checks
        new_orders = result.get('new_sales_orders', [])
        order_lines_map = result.get('order_lines', {})

        if not new_orders:
            feedback_parts.append("No new SO created for Patio Fun Inc.")
            return {
                "passed": score >= 70,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }

        # Pick best SO (prefer any order over none)
        best_so = new_orders[0]
        so_id = best_so['c_order_id']

        # Criterion 4: New SO created
        score += 15
        feedback_parts.append(f"New SO {so_id} created for Patio Fun Inc. ✓")

        lines = order_lines_map.get(str(so_id), [])

        # Criterion 5: Patio Chair qty >= 20
        chair_qty = sum(l.get('qty', 0) for l in lines if l.get('m_product_id') == PATIO_CHAIR_ID)
        if chair_qty >= 20:
            score += 17
            feedback_parts.append(f"Patio Chair qty={chair_qty} ✓")
        else:
            feedback_parts.append(f"Patio Chair qty={chair_qty} (expected ≥20)")

        # Criterion 6: Patio Table qty >= 8
        table_qty = sum(l.get('qty', 0) for l in lines if l.get('m_product_id') == PATIO_TABLE_ID)
        if table_qty >= 8:
            score += 17
            feedback_parts.append(f"Patio Table qty={table_qty} ✓")
        else:
            feedback_parts.append(f"Patio Table qty={table_qty} (expected ≥8)")

        # Criterion 7: Patio Sun Screen qty >= 12
        screen_qty = sum(l.get('qty', 0) for l in lines if l.get('m_product_id') == PATIO_SCREEN_ID)
        if screen_qty >= 12:
            score += 16
            feedback_parts.append(f"Patio Sun Screen qty={screen_qty} ✓")
        else:
            feedback_parts.append(f"Patio Sun Screen qty={screen_qty} (expected ≥12)")

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
