#!/usr/bin/env python3
"""
Verifier for replenishment_rules_procurement task.

Scoring (100 points total):
- 10 pts each: reorder rule created for REPR-001, 002, 003, 004, 005 (50 pts)
- 15 pts: REPR-001 (zero stock — most critical) has a rule with min_qty > 0
- 15 pts: REPR-002 (zero stock — most critical) has a rule with min_qty > 0
- 10 pts: at least one new procurement/purchase order generated from replenishment
- 10 pts: REPR-006 and REPR-007 (adequate stock) do NOT have new reorder rules

Pass threshold: 55 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_replenishment_rules_procurement(traj, env_info, task_info):
    """
    Verify that the agent correctly identified undersupplied products,
    created reorder rules, and triggered procurement.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    low_stock_skus = metadata.get('low_stock_skus',
        ['REPR-001', 'REPR-002', 'REPR-003', 'REPR-004', 'REPR-005'])
    high_stock_skus = metadata.get('high_stock_skus', ['REPR-006', 'REPR-007'])
    pass_threshold = metadata.get('pass_threshold', 55)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        try:
            copy_from_env('/tmp/replenishment_rules_procurement_result.json', temp_path)
            with open(temp_path, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}
    rules = result.get('reorder_rules', {})
    new_po_count = result.get('new_po_count', 0)
    procurement_lines = result.get('procurement_lines_for_repr', 0)

    # Baseline check — do-nothing detection
    any_rule_created = any(rules.get(code, {}).get('exists', False) for code in low_stock_skus)
    if not any_rule_created and new_po_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No reorder rules created and no purchase orders found — agent made no changes"
        }

    # Criterion 1: Reorder rules for each low-stock product (10 pts each)
    for code in low_stock_skus:
        rule = rules.get(code, {})
        if rule.get('exists') and rule.get('min_qty', 0) > 0:
            score += 10
            subscores[code] = True
            feedback_parts.append(f"{code}: ✓ rule created (min={rule.get('min_qty')}, max={rule.get('max_qty')})")
        else:
            subscores[code] = False
            feedback_parts.append(f"{code}: ✗ no rule")

    # Criterion 2: Critical products bonus (REPR-001 and REPR-002 were at 0/5 units)
    critical_done = 0
    for critical_code in ['REPR-001', 'REPR-002']:
        if rules.get(critical_code, {}).get('exists') and rules.get(critical_code, {}).get('min_qty', 0) > 0:
            critical_done += 1
    if critical_done == 2:
        score += 15
        feedback_parts.append("Critical products (REPR-001, REPR-002) covered (+15)")
    elif critical_done == 1:
        score += 7
        feedback_parts.append("One critical product covered (+7)")

    # Criterion 3: Procurement orders generated (10 pts)
    if new_po_count > 0 or procurement_lines > 0:
        score += 10
        subscores['procurement_generated'] = True
        feedback_parts.append(f"Procurement orders generated (new_po={new_po_count}, lines={procurement_lines}) (+10)")
    else:
        subscores['procurement_generated'] = False
        feedback_parts.append("No procurement orders found — replenishment not run")

    # Criterion 4: High-stock products should NOT have rules (10 pts)
    high_stock_no_rules = all(
        not rules.get(code, {}).get('exists', False)
        for code in high_stock_skus
    )
    if high_stock_no_rules:
        score += 10
        subscores['high_stock_untouched'] = True
        feedback_parts.append("High-stock products (REPR-006, REPR-007) correctly NOT given rules (+10)")
    else:
        subscores['high_stock_untouched'] = False
        feedback_parts.append("Warning: rules created for products with adequate stock")
        score -= 5  # Penalty for poor judgment (creating rules where not needed)

    # Cap score at 0 minimum
    score = max(0, score)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "No actions detected",
        "subscores": subscores,
        "debug": {
            "rules_created": sum(1 for code in low_stock_skus if rules.get(code, {}).get('exists')),
            "new_po_count": new_po_count,
            "procurement_lines": procurement_lines,
        }
    }
