#!/usr/bin/env python3
"""Verifier for Create Configurable Product task in Magento.

Task: Create a configurable product TMS-BP-45L (Trailmaster Summit Backpack 45L)
with two color variants (Black: TMS-BP-45L-BLK at $149.99 qty 30,
Green: TMS-BP-45L-GRN at $159.99 qty 25), assigned to Sports category.

Scored on 6 independent criteria (100 pts total).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_product(traj, env_info, task_info):
    """
    Verify configurable product creation with variants.

    Criteria (weighted):
    1. Parent configurable product exists with SKU TMS-BP-45L (15 pts)
    2. Parent product type is 'configurable' (15 pts)
    3. Both child SKUs exist: TMS-BP-45L-BLK and TMS-BP-45L-GRN (25 pts)
    4. Child products are linked via super attribute / relation (20 pts)
    5. Parent product is assigned to Sports category (15 pts)
    6. Green variant price is $159.99 (different from parent $149.99) (10 pts)

    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env function in env_info"}

    # Gate: must be a copy_from_env style function
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/configure_product_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result: {e}"}
    except Exception as e:
        logger.error(f"Error copying result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result data: {result}")

    score = 0
    feedback_parts = []
    subscores = {}

    # ── GATE: Parent product must exist ──────────────────────────────────────
    parent_found = result.get('parent_found', False)
    if not parent_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "GATE FAIL: Parent product with SKU 'TMS-BP-45L' not found in database. "
                        "Configurable product was not created.",
            "subscores": {
                "parent_exists": False, "is_configurable": False,
                "both_children_exist": False, "children_linked": False,
                "sports_category": False, "green_variant_price": False
            }
        }

    # ── Criterion 1: Parent product exists with correct SKU (15 pts) ─────────
    parent_sku = result.get('parent_sku', '').strip().lower()
    sku_ok = parent_sku == 'tms-bp-45l'
    if sku_ok:
        score += 15
        feedback_parts.append("Parent SKU TMS-BP-45L exists (15 pts)")
    else:
        feedback_parts.append(f"Parent SKU mismatch: expected 'TMS-BP-45L', got '{parent_sku}'")
    subscores['parent_exists'] = sku_ok

    # ── Criterion 2: Product type is 'configurable' (15 pts) ─────────────────
    is_configurable = result.get('parent_is_configurable', False)
    if is_configurable:
        score += 15
        feedback_parts.append("Product type is 'configurable' (15 pts)")
    else:
        feedback_parts.append("Product type is NOT 'configurable' — must use Configurable Product, not Simple")
    subscores['is_configurable'] = is_configurable

    # ── GATE: Both children missing → cap at current score ───────────────────
    black_found = result.get('black_child_found', False)
    green_found = result.get('green_child_found', False)

    # ── Criterion 3: Both child SKUs exist (25 pts total) ────────────────────
    child_score = 0
    if black_found:
        child_score += 12
        feedback_parts.append("Black child TMS-BP-45L-BLK exists")
    else:
        feedback_parts.append("MISSING: Black child product TMS-BP-45L-BLK not found")

    if green_found:
        child_score += 13
        feedback_parts.append("Green child TMS-BP-45L-GRN exists")
    else:
        feedback_parts.append("MISSING: Green child product TMS-BP-45L-GRN not found")

    score += child_score
    subscores['both_children_exist'] = (black_found and green_found)

    # ── Criterion 4: Children linked to parent (20 pts) ──────────────────────
    child_count = result.get('child_count_in_relation', 0)
    super_attr_any = result.get('super_attr_any_count', 0)
    super_attr_color = result.get('super_attr_color_count', 0)

    # Linked if: relation table has ≥2 children OR super attribute exists
    children_linked = (child_count >= 2) or (super_attr_any >= 1 and (black_found or green_found))
    if children_linked:
        score += 20
        link_detail = f"child_count={child_count}, super_attrs={super_attr_any}"
        feedback_parts.append(f"Children linked to parent via configurable attribute ({link_detail}) (20 pts)")
    else:
        feedback_parts.append(
            f"Children NOT linked to parent (child_count_in_relation={child_count}, "
            f"super_attr_any={super_attr_any}). Create variants through the Configurations tab."
        )
    subscores['children_linked'] = children_linked

    # ── Criterion 5: Sports category assigned (15 pts) ───────────────────────
    sports_assigned = result.get('category_assigned_sports', False)
    if sports_assigned:
        score += 15
        feedback_parts.append("Product assigned to Sports category (15 pts)")
    else:
        feedback_parts.append("Product NOT assigned to Sports category")
    subscores['sports_category'] = sports_assigned

    # ── Criterion 6: Green variant has distinct higher price $159.99 (10 pts) ─
    green_price_str = result.get('green_child_price', '')
    green_price_ok = False
    try:
        gp = float(green_price_str) if green_price_str else 0.0
        green_price_ok = abs(gp - 159.99) < 0.02
    except (ValueError, TypeError):
        pass

    if green_price_ok:
        score += 10
        feedback_parts.append("Green variant price $159.99 correct (10 pts)")
    else:
        feedback_parts.append(
            f"Green variant price incorrect: expected $159.99, got '{green_price_str}'"
        )
    subscores['green_variant_price'] = green_price_ok

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
