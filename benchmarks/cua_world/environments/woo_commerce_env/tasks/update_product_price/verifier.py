#!/usr/bin/env python3
"""
Verifier for Update Product Price task in WooCommerce.

This is a harder task that requires the agent to:
1. Find an existing product in the catalog
2. Navigate to its edit page
3. Update the regular price
4. Add a sale price
5. Save/update the product

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points):
  1. Product still exists (5 pts)
  2. Regular price changed from original (10 pts)
  3. Regular price matches expected (15 pts)
  4. Sale price set (10 pts)
  5. Sale price matches expected (15 pts)
  6. Product integrity preserved - name/SKU unchanged (15 pts)

VLM checks (30 points):
  7. Process verification (15 pts): trajectory shows product search/navigation and editing
  8. Final state verification (10 pts): shows updated product or success message
  9. Cross-validation (5 pts)

Pass threshold: 60 points AND product found AND prices changed AND
(VLM confirms workflow OR VLM unavailable)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent updating a product price in a WooCommerce store via the WordPress admin interface.

The images are sampled chronologically from the agent's full interaction (earliest to latest).

For a successful product price update, the agent should:
1. Start at the WordPress admin dashboard (already logged in)
2. Navigate to Products (product list or search for a specific product)
3. Open a specific product's edit page
4. Modify the price fields (regular price and/or sale price)
5. Click Update/Save to save the changes

Assess:
1. WORKFLOW_COMPLETED: Did the agent find a product and edit its price fields?
2. PRODUCT_EDIT_VISIBLE: Is a product edit page visible at any point with price fields?
3. SAVE_CONFIRMED: Is there evidence the product was saved/updated?
4. MEANINGFUL_PROGRESSION: Do the frames show searching for and editing a product (not creating a new one)?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "product_edit_visible": true/false,
    "save_confirmed": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce product price update task.

This is a desktop screenshot showing the WordPress admin interface in a browser.

Assess:
1. ADMIN_VISIBLE: Is the WordPress/WooCommerce admin interface visible (not the login page)?
2. SUCCESS_INDICATORS: Are there success indicators? (e.g., "Product updated" message, product edit page with saved prices)
3. PRICE_FIELDS_VISIBLE: Can you see price fields with values?
4. ERROR_INDICATORS: Are there error messages or warnings?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "price_fields_visible": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_update_product_price(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_regular = metadata.get('expected_regular_price', '59.99')
    expected_sale = metadata.get('expected_sale_price', '49.99')
    original_regular = metadata.get('original_regular_price', '79.99')
    target_name = metadata.get('target_product_name', 'Wireless Bluetooth Headphones')
    target_sku = metadata.get('target_product_sku', 'WBH-001')

    feedback_parts = []
    score = 0
    details = {}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/update_product_price_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {str(e)}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}

    product_found = result.get('product_found', False)
    price_changed = result.get('price_changed', False)
    product = result.get('product', {})

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # 1. Product still exists (5 pts)
    if product_found:
        score += 5
        feedback_parts.append("Product exists")
    else:
        feedback_parts.append("Product NOT found")

    # 2. Regular price changed from original (10 pts)
    regular_price = product.get('regular_price', '')
    try:
        regular_float = float(regular_price) if regular_price else 0
        original_float = float(original_regular) if original_regular else 0
        if abs(regular_float - original_float) > 0.01:
            score += 10
            feedback_parts.append(f"Regular price changed from ${original_regular}")
        else:
            feedback_parts.append("Regular price NOT changed from original")
    except (ValueError, TypeError):
        feedback_parts.append("Regular price could not be compared")

    # 3. Regular price matches expected (15 pts)
    regular_correct = False
    try:
        regular_float = float(regular_price) if regular_price else 0
        expected_float = float(expected_regular)
        if abs(regular_float - expected_float) < 0.01:
            score += 15
            regular_correct = True
            feedback_parts.append(f"Regular price correct: ${expected_regular}")
        elif regular_price:
            feedback_parts.append(f"Regular price mismatch: expected ${expected_regular}, got ${regular_price}")
    except (ValueError, TypeError):
        feedback_parts.append(f"Regular price invalid: '{regular_price}'")

    # 4. Sale price set (10 pts)
    sale_price = product.get('sale_price', '')
    sale_set = bool(sale_price and sale_price.strip())
    if sale_set:
        score += 10
        feedback_parts.append(f"Sale price set: ${sale_price}")
    else:
        feedback_parts.append("Sale price NOT set")

    # 5. Sale price matches expected (15 pts)
    sale_correct = False
    if sale_set:
        try:
            sale_float = float(sale_price)
            expected_sale_float = float(expected_sale)
            if abs(sale_float - expected_sale_float) < 0.01:
                score += 15
                sale_correct = True
                feedback_parts.append(f"Sale price correct: ${expected_sale}")
            else:
                feedback_parts.append(f"Sale price mismatch: expected ${expected_sale}, got ${sale_price}")
        except (ValueError, TypeError):
            feedback_parts.append(f"Sale price invalid: '{sale_price}'")
    else:
        feedback_parts.append("Sale price not set, cannot verify")

    # 6. Product integrity preserved (15 pts)
    name = product.get('name', '')
    sku = product.get('sku', '')
    # Use equality check (not substring) to prevent delete+recreate gaming
    name_ok = name.strip().lower() == target_name.strip().lower() if name else False
    sku_ok = target_sku.lower() == sku.strip().lower() if sku else False

    if name_ok and sku_ok:
        score += 15
        feedback_parts.append("Product integrity: name and SKU preserved")
    elif name_ok:
        score += 10
        feedback_parts.append("Product integrity: name preserved, SKU changed")
    elif sku_ok:
        score += 10
        feedback_parts.append("Product integrity: SKU preserved, name changed")
    else:
        feedback_parts.append("Product integrity issue: name or SKU may have been modified")

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================

    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')
    vlm_workflow_confirmed = False
    vlm_available = False

    sampled_frames = sample_frames(traj, num_samples=6) if sample_frames else []
    final_frame = get_final(traj) if get_final else None

    has_trajectory = len(sampled_frames) >= 2
    has_final = final_frame is not None

    details['vlm_trajectory_frames'] = len(sampled_frames)
    details['vlm_has_final_frame'] = has_final

    if query_vlm and (has_trajectory or has_final):
        vlm_available = True

        if has_trajectory:
            process_result = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames)
            details['vlm_process'] = process_result
            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                progression_ok = process_result.get('meaningful_progression', False)
                edit_visible = process_result.get('product_edit_visible', False)
                if workflow_ok and progression_ok:
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Full edit workflow confirmed")
                elif workflow_ok or edit_visible:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Edit workflow partially confirmed")
                elif progression_ok:
                    score += 5
                    feedback_parts.append("VLM process: Some progression seen")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")

        if has_final:
            final_result = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
            details['vlm_final_state'] = final_result
            if final_result:
                admin_ok = final_result.get('admin_visible', False)
                success_ok = final_result.get('success_indicators', False)
                if admin_ok and success_ok:
                    score += 10
                    feedback_parts.append("VLM final: Success indicators visible")
                elif admin_ok:
                    score += 4
                    feedback_parts.append("VLM final: Admin visible, no success indicators")

        if product_found and price_changed and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: DB price change + VLM workflow")
            details['cross_validation'] = 'pass'
        elif product_found and price_changed:
            details['cross_validation'] = 'mismatch'
        else:
            details['cross_validation'] = 'neither'
    else:
        feedback_parts.append("VLM checks skipped (unavailable)")

    # ================================================================
    # PASS CRITERIA
    # ================================================================
    if vlm_available:
        passed = score >= 60 and product_found and price_changed and vlm_workflow_confirmed
    else:
        passed = score >= 60 and product_found and price_changed

    details.update({
        "product_found": product_found,
        "price_changed": price_changed,
        "regular_correct": regular_correct,
        "sale_correct": sale_correct,
        "vlm_available": vlm_available,
        "vlm_workflow_confirmed": vlm_workflow_confirmed,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
