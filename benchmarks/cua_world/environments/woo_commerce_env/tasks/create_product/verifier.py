#!/usr/bin/env python3
"""
Verifier for Create Product task in WooCommerce.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) — from export script JSON inside container:
  1. Product exists in database (15 pts)
  2. SKU matches expected value (10 pts)
  3. Product name matches expected value (10 pts)
  4. Price matches expected value (10 pts)
  5. Category assigned correctly (10 pts)
  6. Product type is 'simple' (5 pts)
  7. Product status is 'publish' (5 pts)
  8. Product was newly created (5 pts)

VLM checks (30 points) — using TRAJECTORY frames (framework-captured):
  9. Process verification (15 pts): Sampled trajectory frames show the agent
     navigating WooCommerce admin, filling product form, and publishing.
  10. Final state verification (10 pts): Final frame shows WooCommerce admin
      with product created or success message.
  11. Cross-validation (5 pts): Programmatic product found agrees with VLM
      seeing product creation workflow.

Pass threshold: 60 points AND product found AND VLM trajectory confirms workflow
(when VLM is available)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ================================================================
# VLM HELPERS
# ================================================================

def _vlm_query(query_vlm, prompt, image=None, images=None):
    """Run VLM query with single or multiple images. Returns parsed dict or None."""
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


# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a product in a WooCommerce store via the WordPress admin interface.

The images are sampled chronologically from the agent's full interaction (earliest to latest).

For successful product creation, the agent should progress through these stages:
1. WordPress admin dashboard visible (already logged in)
2. Navigation to Products section (Products menu, Add New Product page)
3. Product form being filled in (product name, price, SKU fields visible)
4. Product published (success message, product visible in product list, or Publish button clicked)

Assess:
1. WORKFLOW_COMPLETED: Did the agent progress through at least navigating to the product form AND filling in details?
2. PRODUCT_FORM_VISIBLE: At any point, is the WooCommerce "Add new product" form visible with fields being filled?
3. PUBLISH_CONFIRMED: Is there evidence the product was published (success message, product list showing new product)?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes (not the same screen repeated)?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "product_form_visible": true/false,
    "publish_confirmed": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages you can identify"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce product creation task.

This is a desktop screenshot showing the WordPress admin interface in a browser.

Assess:
1. ADMIN_VISIBLE: Is the WordPress/WooCommerce admin interface visible (not the login page)?
2. SUCCESS_INDICATORS: Are there any success indicators visible? (e.g., "Product published" message, product visible in list, edit product page showing saved product)
3. PRODUCT_DATA_VISIBLE: Can you see any product details (name, price, SKU) that were entered?
4. ERROR_INDICATORS: Are there any error messages or warnings visible?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "product_data_visible": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_create_product(traj, env_info, task_info):
    """
    Verify that the expected product was created in WooCommerce.

    Scoring (100 points total):
    Programmatic (70 pts): product exists, SKU, name, price, category, type, status, newly created
    VLM (30 pts): trajectory process (15), final state (10), cross-validation (5)

    Pass threshold: 60 points AND product found in database AND
    (VLM confirms workflow OR VLM unavailable)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Handcrafted Leather Wallet')
    expected_sku = metadata.get('expected_sku', 'HLW-BRN-01')
    expected_price = metadata.get('expected_price', '45.99')
    expected_category = metadata.get('expected_category', 'Accessories')
    expected_type = metadata.get('expected_type', 'simple')
    expected_status = metadata.get('expected_status', 'publish')

    feedback_parts = []
    score = 0
    details = {}

    # ================================================================
    # Load result file from container
    # ================================================================
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_product_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False, "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    initial_count = result.get('initial_product_count', 0)
    current_count = result.get('current_product_count', 0)
    product_found = result.get('product_found', False)
    product = result.get('product', {})

    logger.info(f"Result: initial={initial_count}, current={current_count}, found={product_found}")
    logger.info(f"Product data: {product}")

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points total)
    # ================================================================

    # Criterion 1: Product exists in database (15 points)
    if product_found:
        score += 15
        feedback_parts.append("Product found in database")
    else:
        feedback_parts.append("Product NOT found in database")
        if current_count > initial_count:
            feedback_parts.append(f"Note: {current_count - initial_count} new product(s) added but not matching expected")
        else:
            feedback_parts.append("No new products were added")

    # Criterion 2: SKU matches (10 points)
    sku = product.get('sku', '')
    sku_correct = sku.strip().lower() == expected_sku.strip().lower()
    if sku_correct:
        score += 10
        feedback_parts.append(f"SKU correct: {expected_sku}")
    elif sku:
        feedback_parts.append(f"SKU mismatch: expected '{expected_sku}', got '{sku}'")
    else:
        feedback_parts.append("SKU not set")

    # Criterion 3: Name matches (10 points) - EXACT match only (no partial credit)
    name = product.get('name', '')
    name_correct = name.strip().lower() == expected_name.strip().lower()
    if name_correct:
        score += 10
        feedback_parts.append(f"Product name correct: {expected_name}")
    elif name:
        feedback_parts.append(f"Product name mismatch: expected '{expected_name}', got '{name}'")
    else:
        feedback_parts.append("Product name not set")

    # Criterion 4: Price matches (10 points)
    price = product.get('price', '')
    price_correct = False
    try:
        actual_price = float(price) if price else 0
        expected_price_float = float(expected_price)
        if abs(actual_price - expected_price_float) < 0.01:
            score += 10
            price_correct = True
            feedback_parts.append(f"Price correct: ${expected_price}")
        elif price:
            feedback_parts.append(f"Price mismatch: expected ${expected_price}, got ${price}")
        else:
            feedback_parts.append("Price not set")
    except (ValueError, TypeError):
        feedback_parts.append(f"Price could not be verified: '{price}'")

    # Criterion 5: Category assigned correctly (10 points)
    categories = product.get('categories', '')
    category_correct = False
    if categories:
        cat_list = [c.strip().lower() for c in categories.split(',')]
        if expected_category.strip().lower() in cat_list:
            score += 10
            category_correct = True
            feedback_parts.append(f"Category correct: {expected_category}")
        else:
            feedback_parts.append(f"Category mismatch: expected '{expected_category}', got '{categories}'")
    else:
        feedback_parts.append("No category assigned")

    # Criterion 6: Product type is correct (5 points)
    product_type = product.get('type', '')
    type_correct = product_type.strip().lower() == expected_type.strip().lower()
    if type_correct:
        score += 5
        feedback_parts.append(f"Product type correct: {expected_type}")
    elif product_type:
        feedback_parts.append(f"Product type mismatch: expected '{expected_type}', got '{product_type}'")
    else:
        feedback_parts.append("Product type not set")

    # Criterion 7: Product status is publish (5 points)
    product_status = product.get('status', '')
    status_correct = product_status.strip().lower() == expected_status.strip().lower()
    if status_correct:
        score += 5
        feedback_parts.append(f"Product status correct: {expected_status}")
    elif product_status:
        feedback_parts.append(f"Product status mismatch: expected '{expected_status}', got '{product_status}'")
    else:
        feedback_parts.append("Product status not set")

    # Criterion 8: Product was newly created (5 points)
    newly_created = current_count > initial_count
    if newly_created:
        score += 5
        feedback_parts.append("Product count increased (newly created)")
    else:
        feedback_parts.append("Product count unchanged")

    # ================================================================
    # VLM CHECKS (30 points total)
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

        # --- VLM Check A: Process Verification — 15 points ---
        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )
            details['vlm_process'] = process_result

            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                progression_ok = process_result.get('meaningful_progression', False)
                form_visible = process_result.get('product_form_visible', False)

                if workflow_ok and progression_ok:
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Full workflow progression confirmed")
                elif workflow_ok or form_visible:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Workflow partially confirmed")
                elif progression_ok:
                    score += 5
                    feedback_parts.append("VLM process: Some progression but workflow unclear")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")
            else:
                feedback_parts.append("VLM process check failed")
        else:
            feedback_parts.append("VLM process: Insufficient trajectory frames")

        # --- VLM Check B: Final State Verification — 10 points ---
        if has_final:
            final_result = _vlm_query(
                query_vlm, FINAL_STATE_PROMPT, image=final_frame
            )
            details['vlm_final_state'] = final_result

            if final_result:
                admin_ok = final_result.get('admin_visible', False)
                success_ok = final_result.get('success_indicators', False)
                error_found = final_result.get('error_indicators', False)

                if admin_ok and success_ok and not error_found:
                    score += 10
                    feedback_parts.append("VLM final: Admin visible with success indicators")
                elif admin_ok and success_ok:
                    score += 7
                    feedback_parts.append("VLM final: Success indicators with warnings")
                elif admin_ok:
                    score += 4
                    feedback_parts.append("VLM final: Admin visible but no success indicators")
                else:
                    feedback_parts.append("VLM final: Admin interface not visible")
            else:
                feedback_parts.append("VLM final state check failed")
        else:
            feedback_parts.append("VLM final: No final frame available")

        # --- VLM Check C: Cross-validation — 5 points ---
        if product_found and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: DB product + VLM workflow agree")
            details['cross_validation'] = 'pass'
        elif product_found and not vlm_workflow_confirmed:
            feedback_parts.append("Cross-validation mismatch: product in DB but workflow not confirmed by VLM")
            details['cross_validation'] = 'mismatch'
        elif vlm_workflow_confirmed and not product_found:
            score += 2
            feedback_parts.append("Cross-validation: VLM sees workflow but product not in DB")
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'

    else:
        # VLM not available — no free points, just note it
        feedback_parts.append("VLM checks skipped (unavailable)")

    # ================================================================
    # PASS CRITERIA
    # ================================================================

    # Must have product found AND score >= 60
    # When VLM is available, must also have VLM confirmation
    if vlm_available:
        passed = score >= 60 and product_found and vlm_workflow_confirmed
    else:
        passed = score >= 60 and product_found

    details.update({
        "product_found": product_found,
        "sku_correct": sku_correct,
        "name_correct": name_correct,
        "price_correct": price_correct,
        "category_correct": category_correct,
        "type_correct": type_correct,
        "status_correct": status_correct,
        "newly_created": newly_created,
        "vlm_available": vlm_available,
        "vlm_workflow_confirmed": vlm_workflow_confirmed,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
