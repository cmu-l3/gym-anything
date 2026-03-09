#!/usr/bin/env python3
"""
Verifier for Setup Variable Product with Inventory task in WooCommerce.

This is a very_hard task requiring the agent to:
1. Create a variable product with correct name and SKU
2. Add Color and Size attributes with specific values
3. Generate 6 variations (3 colors x 2 sizes)
4. Set per-variation prices by size
5. Set per-variation stock quantities
6. Configure cross-sells
7. Assign to Clothing category
8. Publish

Verification Strategy (Hybrid: Programmatic + VLM):

Programmatic checks (70 points):
  1. Product exists with correct name and SKU (10 pts)
  2. Product type is 'variable' (5 pts)
  3. Product category is 'Clothing' (5 pts)
  4. Product has 6 variations (10 pts)
  5. Variation prices correct by size (15 pts)
  6. Variation stock quantities correct (15 pts)
  7. Cross-sell linked to Merino Wool Sweater (5 pts)
  8. Product published (5 pts)

VLM checks (30 points):
  9. Process verification (15 pts)
  10. Final state verification (10 pts)
  11. Cross-validation (5 pts)

Pass threshold: 50 points AND product found AND product is variable type AND
at least 4 variations exist
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a variable product with inventory in a WooCommerce store via the WordPress admin interface.

The images are sampled chronologically (earliest to latest).

For successful variable product creation, the agent should:
1. Navigate to Products > Add New
2. Set product type to 'Variable product'
3. Add product attributes (Color, Size) under the Attributes tab
4. Generate variations under the Variations tab
5. Set prices and stock for individual variations
6. Configure cross-sells under the Linked Products tab
7. Publish the product

Assess:
1. WORKFLOW_COMPLETED: Did the agent progress through creating a variable product with variations?
2. VARIABLE_PRODUCT_SETUP: Is the product type dropdown set to 'Variable product' at any point?
3. MULTI_TAB_NAVIGATION: Did the agent use multiple product data tabs (Attributes, Variations, Linked Products)?
4. SAVE_CONFIRMED: Is there evidence the product was published?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "variable_product_setup": true/false,
    "multi_tab_navigation": true/false,
    "save_confirmed": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce variable product creation task.

This is a desktop screenshot showing the WordPress admin interface.

Assess:
1. ADMIN_VISIBLE: Is the WordPress/WooCommerce admin interface visible?
2. SUCCESS_INDICATORS: Are there success indicators (product published, saved)?
3. PRODUCT_PAGE: Is a product editing page visible with product data tabs?
4. ERROR_INDICATORS: Are there error messages?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "product_page": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_setup_variable_product_with_inventory(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Premium Merino Wool Scarf')
    expected_sku = metadata.get('expected_sku', 'PMWS-001')
    price_by_size = metadata.get('price_by_size', {})
    stock_by_combo = metadata.get('stock_by_combination', {})

    feedback_parts = []
    score = 0
    details = {}

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/setup_variable_product_result.json", temp_result.name)
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
    product = result.get('product', {})
    variations = result.get('variations', [])

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # 1. Product exists with correct name and SKU (10 pts)
    if product_found:
        name = product.get('name', '')
        name_ok = expected_name.lower() in name.lower() or name.lower() in expected_name.lower()
        if name_ok:
            score += 10
            feedback_parts.append(f"Product found: '{name}'")
        else:
            score += 5
            feedback_parts.append(f"Product found but name mismatch: expected '{expected_name}', got '{name}'")
    else:
        feedback_parts.append("Product NOT found (SKU PMWS-001)")

    # 2. Product type is 'variable' (5 pts)
    product_type = product.get('type', '').lower().strip()
    is_variable = product_type == 'variable'
    if is_variable:
        score += 5
        feedback_parts.append("Product type: variable")
    elif product_type:
        feedback_parts.append(f"Product type wrong: expected 'variable', got '{product_type}'")
    else:
        feedback_parts.append("Product type not determined")

    # 3. Product category is 'Clothing' (5 pts)
    categories = product.get('categories', '')
    cat_ok = 'clothing' in categories.lower() if categories else False
    if cat_ok:
        score += 5
        feedback_parts.append("Category: Clothing")
    elif categories:
        feedback_parts.append(f"Category mismatch: expected 'Clothing', got '{categories}'")
    else:
        feedback_parts.append("No category assigned")

    # 4. Product has 6 variations (10 pts)
    num_variations = len(variations)
    if num_variations == 6:
        score += 10
        feedback_parts.append("Variations: 6 (correct)")
    elif num_variations >= 4:
        score += 7
        feedback_parts.append(f"Variations: {num_variations} (expected 6, partial credit)")
    elif num_variations >= 2:
        score += 4
        feedback_parts.append(f"Variations: {num_variations} (expected 6)")
    elif num_variations > 0:
        score += 2
        feedback_parts.append(f"Variations: {num_variations} (expected 6)")
    else:
        feedback_parts.append("No variations found")

    # 5. Variation prices correct by size (15 pts)
    prices_correct = 0
    prices_checked = 0
    for var in variations:
        size = var.get('size', '').lower()
        price = var.get('price', '')

        expected_price = None
        if 'standard' in size:
            expected_price = price_by_size.get('Standard', '45.99')
        elif 'oversized' in size:
            expected_price = price_by_size.get('Oversized', '55.99')

        if expected_price and price:
            prices_checked += 1
            try:
                if abs(float(price) - float(expected_price)) < 0.01:
                    prices_correct += 1
            except (ValueError, TypeError):
                pass

    if prices_correct >= 6:
        score += 15
        feedback_parts.append(f"Variation prices: all {prices_correct} correct")
    elif prices_correct >= 4:
        score += 10
        feedback_parts.append(f"Variation prices: {prices_correct}/{prices_checked} correct")
    elif prices_correct >= 2:
        score += 5
        feedback_parts.append(f"Variation prices: {prices_correct}/{prices_checked} correct")
    elif prices_correct > 0:
        score += 2
        feedback_parts.append(f"Variation prices: {prices_correct}/{prices_checked} correct")
    else:
        feedback_parts.append(f"Variation prices: none correct (checked {prices_checked})")

    # 6. Variation stock quantities correct (15 pts)
    stock_correct = 0
    stock_checked = 0
    manage_stock_count = 0

    for var in variations:
        color = var.get('color', '').lower()
        size = var.get('size', '').lower()
        stock = var.get('stock', '')
        manage = var.get('manage_stock', '')

        if manage and manage.lower() == 'yes':
            manage_stock_count += 1

        # Build combo key to match expected
        combo_key = None
        for c in ['burgundy', 'charcoal', 'navy']:
            for s in ['standard', 'oversized']:
                if c in color and s in size:
                    combo_key = f"{c.title()}-{s.title()}"
                    break

        if combo_key and combo_key in stock_by_combo:
            stock_checked += 1
            expected_stock = stock_by_combo[combo_key]
            try:
                if int(float(stock)) == expected_stock:
                    stock_correct += 1
            except (ValueError, TypeError):
                pass

    if stock_correct >= 6:
        score += 15
        feedback_parts.append(f"Variation stock: all {stock_correct} correct")
    elif stock_correct >= 4:
        score += 10
        feedback_parts.append(f"Variation stock: {stock_correct}/{stock_checked} correct")
    elif stock_correct >= 2:
        score += 5
        feedback_parts.append(f"Variation stock: {stock_correct}/{stock_checked} correct")
    elif manage_stock_count > 0:
        score += 2
        feedback_parts.append(f"Stock management enabled on {manage_stock_count} variations but quantities wrong")
    else:
        feedback_parts.append("Variation stock: none correct or stock not managed")

    # 7. Cross-sell linked to Merino Wool Sweater (5 pts)
    cross_sell_ok = product.get('cross_sell_contains_mws', False)
    if cross_sell_ok:
        score += 5
        feedback_parts.append("Cross-sell: Merino Wool Sweater linked")
    else:
        cross_sell_raw = product.get('cross_sell_ids_raw', '')
        if cross_sell_raw and cross_sell_raw not in ('a:0:{}', ''):
            feedback_parts.append("Cross-sell: set but does not include Merino Wool Sweater")
        else:
            feedback_parts.append("Cross-sell: not configured")

    # 8. Product published (5 pts)
    status = product.get('status', '').lower()
    if status == 'publish':
        score += 5
        feedback_parts.append("Product status: published")
    elif status:
        feedback_parts.append(f"Product status: '{status}' (expected 'publish')")
    else:
        feedback_parts.append("Product status unknown")

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
                var_setup = process_result.get('variable_product_setup', False)
                multi_tab = process_result.get('multi_tab_navigation', False)
                if workflow_ok and (var_setup or multi_tab):
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Variable product workflow confirmed")
                elif workflow_ok:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Product workflow confirmed")
                elif var_setup or multi_tab:
                    score += 5
                    feedback_parts.append("VLM process: Partial progress seen")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")

        if has_final:
            final_result = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_frame)
            details['vlm_final_state'] = final_result
            if final_result:
                admin_ok = final_result.get('admin_visible', False)
                success_ok = final_result.get('success_indicators', False)
                product_page = final_result.get('product_page', False)
                error_found = final_result.get('error_indicators', False)
                if admin_ok and success_ok and not error_found:
                    score += 10
                    feedback_parts.append("VLM final: Success indicators visible")
                elif admin_ok and (success_ok or product_page):
                    score += 7
                    feedback_parts.append("VLM final: Product page visible")
                elif admin_ok:
                    score += 4
                    feedback_parts.append("VLM final: Admin visible")

        if product_found and is_variable and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: Variable product + VLM agree")
            details['cross_validation'] = 'pass'
        else:
            details['cross_validation'] = 'partial' if vlm_workflow_confirmed else 'neither'
    else:
        feedback_parts.append("VLM checks skipped (unavailable)")

    # ================================================================
    # PASS CRITERIA
    # ================================================================
    min_variations_ok = num_variations >= 4

    if vlm_available:
        passed = score >= 50 and product_found and is_variable and min_variations_ok and vlm_workflow_confirmed
    else:
        passed = score >= 50 and product_found and is_variable and min_variations_ok

    details.update({
        "product_found": product_found,
        "is_variable": is_variable,
        "num_variations": num_variations,
        "prices_correct": prices_correct,
        "stock_correct": stock_correct,
        "manage_stock_count": manage_stock_count,
        "cross_sell_ok": cross_sell_ok,
        "cat_ok": cat_ok,
        "vlm_available": vlm_available,
        "vlm_workflow_confirmed": vlm_workflow_confirmed,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
