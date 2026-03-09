#!/usr/bin/env python3
"""
Verifier for inventory_product_cycle task.

Reads the JSON exported by export_result.sh via copy_from_env.

Scoring (100 points, pass >= 65):
  15 pts  Chai Tea with price ~$19.50
  15 pts  English Breakfast Tea with price ~$16.00
  10 pts  Darjeeling Reserve with price ~$34.00
  20 pts  Sales invoice for Alfreds ~$257.50
  20 pts  Receipt for ~$128.75
  20 pts  Credit note for ~$39.00
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_inventory_product_cycle(traj, env_info, task_info):
    """Verify inventory product cycle task completion."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/inventory_product_cycle_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    criteria = {}
    new_items = result.get("new_item_count", 0)
    new_invoices = result.get("new_invoice_count", 0)
    new_receipts = result.get("new_receipt_count", 0)
    new_cn = result.get("new_cn_count", 0)

    c1 = result.get("has_chai_tea_19_50", False) and new_items > 0
    if c1:
        score += 15
    criteria["chai_tea_19_50"] = {"passed": c1, "points": 15 if c1 else 0, "max_points": 15}

    c2 = result.get("has_english_breakfast_16_00", False) and new_items > 0
    if c2:
        score += 15
    criteria["english_breakfast_16_00"] = {"passed": c2, "points": 15 if c2 else 0, "max_points": 15}

    c3 = result.get("has_darjeeling_34_00", False) and new_items > 0
    if c3:
        score += 10
    criteria["darjeeling_reserve_34_00"] = {"passed": c3, "points": 10 if c3 else 0, "max_points": 10}

    c4 = result.get("has_invoice_alfreds_257_50", False) and new_invoices > 0
    if c4:
        score += 20
    criteria["invoice_alfreds_257_50"] = {"passed": c4, "points": 20 if c4 else 0, "max_points": 20}

    c5 = result.get("has_receipt_128_75", False) and new_receipts > 0
    if c5:
        score += 20
    criteria["receipt_128_75"] = {"passed": c5, "points": 20 if c5 else 0, "max_points": 20}

    c6 = result.get("has_credit_note_39_00", False) and new_cn > 0
    if c6:
        score += 20
    criteria["credit_note_39_00"] = {"passed": c6, "points": 20 if c6 else 0, "max_points": 20}

    passed = score >= 65
    feedback_parts = [f"Score: {score}/100"]
    for name, c in criteria.items():
        feedback_parts.append(f"  [{'PASS' if c['passed'] else 'FAIL'}] {name}: {c['points']}/{c['max_points']} pts")
    return {"passed": passed, "score": score, "feedback": "\n".join(feedback_parts), "criteria": criteria}
