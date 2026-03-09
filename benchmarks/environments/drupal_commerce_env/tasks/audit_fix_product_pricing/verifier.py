#!/usr/bin/env python3
"""Verifier for audit_fix_product_pricing task.

Scoring (100 points):
- Criterion 1: Bose price updated to $279.00 — 20 points
- Criterion 2: WD SSD price updated to $129.99 — 20 points
- Criterion 3: Corsair SKU changed to CORSAIR-DDR5-32GB — 20 points
- Criterion 4: Sony list price set to $399.99 (selling price unchanged) — 20 points
- Criterion 5: Anker product unpublished — 20 points

Pass threshold: 60 points (3 of 5 subtasks)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_audit_fix_product_pricing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/audit_fix_product_pricing_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # GATE: check if ANY changes were made
    any_change = (
        result.get('bose_price_changed') or
        result.get('wd_price_changed') or
        result.get('corsair_sku_changed') or
        result.get('sony_list_price_set') or
        result.get('anker_unpublished')
    )
    if not any_change:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No product changes detected — no work was done"
        }

    # Criterion 1: Bose price updated to $279.00 (20 pts)
    try:
        bose_price_str = result.get('bose_current_price', '0')
        bose_price = float(bose_price_str)
        if abs(bose_price - 279.00) < 0.01:
            score += 20
            subscores["bose_price"] = True
            feedback_parts.append("Bose price corrected to $279.00")
        elif result.get('bose_price_changed'):
            score += 5
            feedback_parts.append(f"Bose price changed but to ${bose_price:.2f} (expected $279.00)")
        else:
            feedback_parts.append(f"Bose price unchanged at ${bose_price:.2f}")
    except Exception as e:
        feedback_parts.append(f"Bose price check error: {e}")

    # Criterion 2: WD SSD price updated to $129.99 (20 pts)
    try:
        wd_price_str = result.get('wd_current_price', '0')
        wd_price = float(wd_price_str)
        if abs(wd_price - 129.99) < 0.01:
            score += 20
            subscores["wd_price"] = True
            feedback_parts.append("WD SSD price corrected to $129.99")
        elif result.get('wd_price_changed'):
            score += 5
            feedback_parts.append(f"WD price changed but to ${wd_price:.2f} (expected $129.99)")
        else:
            feedback_parts.append(f"WD price unchanged at ${wd_price:.2f}")
    except Exception as e:
        feedback_parts.append(f"WD price check error: {e}")

    # Criterion 3: Corsair SKU changed to CORSAIR-DDR5-32GB (20 pts)
    try:
        corsair_sku = result.get('corsair_current_sku', '').strip()
        expected_sku = metadata.get('corsair_expected_sku', 'CORSAIR-DDR5-32GB')
        if corsair_sku.upper() == expected_sku.upper():
            score += 20
            subscores["corsair_sku"] = True
            feedback_parts.append(f"Corsair SKU corrected to {corsair_sku}")
        elif result.get('corsair_sku_changed'):
            score += 5
            feedback_parts.append(f"Corsair SKU changed to '{corsair_sku}' (expected '{expected_sku}')")
        else:
            feedback_parts.append(f"Corsair SKU unchanged: {corsair_sku}")
    except Exception as e:
        feedback_parts.append(f"Corsair SKU check error: {e}")

    # Criterion 4: Sony list price set to $399.99, selling price unchanged (20 pts)
    try:
        sony_list_set = result.get('sony_list_price_set', False)
        sony_list_str = result.get('sony_current_list_price', 'NULL')
        sony_price_str = result.get('sony_current_price', '0')

        if sony_list_set:
            try:
                sony_list = float(sony_list_str)
                sony_price = float(sony_price_str)
                if abs(sony_list - 399.99) < 0.01 and abs(sony_price - 348.00) < 0.01:
                    score += 20
                    subscores["sony_list_price"] = True
                    feedback_parts.append("Sony list price set to $399.99, selling price unchanged")
                elif abs(sony_list - 399.99) < 0.01:
                    score += 15
                    feedback_parts.append(f"Sony list price correct but selling price changed to ${sony_price:.2f}")
                else:
                    score += 5
                    feedback_parts.append(f"Sony list price set to ${sony_list:.2f} (expected $399.99)")
            except (ValueError, TypeError):
                score += 5
                feedback_parts.append(f"Sony list price set but parse error: {sony_list_str}")
        else:
            feedback_parts.append("Sony list price not set")
    except Exception as e:
        feedback_parts.append(f"Sony list price check error: {e}")

    # Criterion 5: Anker unpublished (20 pts)
    try:
        if result.get('anker_unpublished'):
            score += 20
            subscores["anker_unpublished"] = True
            feedback_parts.append("Anker product unpublished")
        else:
            anker_status = result.get('anker_current_status', '1')
            feedback_parts.append(f"Anker still published (status={anker_status})")
    except Exception as e:
        feedback_parts.append(f"Anker status check error: {e}")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No criteria met",
        "subscores": subscores
    }
