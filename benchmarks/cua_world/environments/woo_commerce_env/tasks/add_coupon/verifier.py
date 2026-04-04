#!/usr/bin/env python3
"""
Verifier for Add Coupon task in WooCommerce.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) — from export script JSON inside container:
  1. Coupon exists in database (10 pts)
  2. Coupon code matches expected value (15 pts)
  3. Discount type is percentage (10 pts)
  4. Discount amount matches (10 pts)
  5. Usage limit matches (10 pts)
  6. Minimum spend matches (10 pts)
  6b. Coupon newly created (5 pts)

VLM checks (30 points) — using TRAJECTORY frames (framework-captured):
  7. Process verification (15 pts): Sampled trajectory frames show the agent
     navigating to Marketing > Coupons, filling coupon form, and publishing.
  8. Final state verification (10 pts): Final frame shows coupon created
     or success message.
  9. Cross-validation (5 pts): Programmatic coupon found agrees with VLM
     seeing coupon creation workflow.

Pass threshold: 55 points AND coupon found AND VLM trajectory confirms workflow
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

TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent creating a coupon in a WooCommerce store via the WordPress admin interface.

The images are sampled chronologically from the agent's full interaction (earliest to latest).

For successful coupon creation, the agent should progress through these stages:
1. WordPress admin dashboard visible (already logged in)
2. Navigation to coupon creation area (Marketing > Coupons or WooCommerce > Coupons)
3. Add Coupon page visible with fields being filled (coupon code, discount type, amount)
4. Usage restriction tab configured (usage limit, minimum spend)
5. Coupon published (success message or coupon visible in coupon list)

Assess:
1. WORKFLOW_COMPLETED: Did the agent progress through navigating to coupons AND filling in details?
2. COUPON_FORM_VISIBLE: At any point, is the WooCommerce "Add coupon" form visible with fields being filled?
3. PUBLISH_CONFIRMED: Is there evidence the coupon was published?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes (not the same screen repeated)?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "coupon_form_visible": true/false,
    "publish_confirmed": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages you can identify"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce coupon creation task.

This is a desktop screenshot showing the WordPress admin interface in a browser.

Assess:
1. ADMIN_VISIBLE: Is the WordPress/WooCommerce admin interface visible (not the login page)?
2. SUCCESS_INDICATORS: Are there any success indicators? (e.g., "Coupon updated" or "published" message, coupon in list)
3. COUPON_DATA_VISIBLE: Can you see any coupon details (code, discount, amount)?
4. ERROR_INDICATORS: Are there any error messages or warnings?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "coupon_data_visible": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_add_coupon(traj, env_info, task_info):
    """
    Verify that the expected coupon was created in WooCommerce.

    Scoring (100 points total):
    Programmatic (70 pts): coupon exists (10), code (15), type (10), amount (10), usage limit (10), min spend (10), newly created (5)
    VLM (30 pts): trajectory process (15), final state (10), cross-validation (5)

    Pass threshold: 55 points AND coupon found AND
    (VLM confirms workflow OR VLM unavailable)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_code = metadata.get('expected_code', 'SUMMER25')
    expected_discount_type = metadata.get('expected_discount_type', 'percent')
    expected_amount = metadata.get('expected_amount', '25')
    expected_usage_limit = metadata.get('expected_usage_limit', '50')
    expected_min_spend = metadata.get('expected_minimum_amount', '75')

    feedback_parts = []
    score = 0
    details = {}

    # ================================================================
    # Load result file from container
    # ================================================================
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_coupon_result.json", temp_result.name)
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

    initial_count = result.get('initial_coupon_count', 0)
    current_count = result.get('current_coupon_count', 0)
    coupon_found = result.get('coupon_found', False)
    coupon = result.get('coupon', {})

    logger.info(f"Result: initial={initial_count}, current={current_count}, found={coupon_found}")
    logger.info(f"Coupon data: {coupon}")

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points total)
    # ================================================================

    # Criterion 1: Coupon exists in database (10 points)
    if coupon_found:
        score += 10
        feedback_parts.append("Coupon found in database")
    else:
        feedback_parts.append("Coupon NOT found in database")
        if current_count > initial_count:
            feedback_parts.append(f"Note: {current_count - initial_count} new coupon(s) added but not matching")
        else:
            feedback_parts.append("No new coupons were added")

    # Criterion 1b: Coupon newly created (5 points)
    newly_created = current_count > initial_count
    if newly_created:
        score += 5
        feedback_parts.append("Coupon count increased (newly created)")
    elif coupon_found:
        feedback_parts.append("Coupon found but count did not increase (may be pre-existing)")
    details['newly_created'] = newly_created

    # Criterion 2: Coupon code matches (15 points) - EXACT match only (case-insensitive per WooCommerce behavior)
    code = coupon.get('code', '')
    code_correct = code.strip().lower() == expected_code.strip().lower()
    if code_correct:
        score += 15
        feedback_parts.append(f"Coupon code correct: {expected_code}")
    elif code:
        feedback_parts.append(f"Coupon code mismatch: expected '{expected_code}', got '{code}'")
    else:
        feedback_parts.append("Coupon code not set")

    # Criterion 3: Discount type is percentage (10 points)
    discount_type = coupon.get('discount_type', '')
    type_variations = ['percent', 'percentage', 'percent_discount', 'percentage_discount']
    type_correct = discount_type.strip().lower() in type_variations if expected_discount_type == 'percent' else \
        discount_type.strip().lower() == expected_discount_type.strip().lower()
    if type_correct:
        score += 10
        feedback_parts.append(f"Discount type correct: {discount_type}")
    elif discount_type:
        feedback_parts.append(f"Discount type mismatch: expected '{expected_discount_type}', got '{discount_type}'")
    else:
        feedback_parts.append("Discount type not set")

    # Criterion 4: Discount amount matches (10 points)
    amount = coupon.get('amount', '')
    amount_correct = False
    try:
        actual_amount = float(amount) if amount else 0
        expected_amount_float = float(expected_amount)
        if abs(actual_amount - expected_amount_float) < 0.01:
            score += 10
            amount_correct = True
            feedback_parts.append(f"Discount amount correct: {expected_amount}")
        elif amount:
            feedback_parts.append(f"Discount amount mismatch: expected {expected_amount}, got {amount}")
        else:
            feedback_parts.append("Discount amount not set")
    except (ValueError, TypeError):
        feedback_parts.append(f"Discount amount could not be verified: '{amount}'")

    # Criterion 5: Usage limit matches (10 points)
    usage_limit = coupon.get('usage_limit', '')
    usage_limit_correct = False
    if usage_limit:
        try:
            if int(float(usage_limit)) == int(float(expected_usage_limit)):
                score += 10
                usage_limit_correct = True
                feedback_parts.append(f"Usage limit correct: {expected_usage_limit}")
            else:
                feedback_parts.append(f"Usage limit mismatch: expected {expected_usage_limit}, got {usage_limit}")
        except (ValueError, TypeError):
            feedback_parts.append(f"Usage limit invalid: '{usage_limit}'")
    else:
        feedback_parts.append("Usage limit not set")

    # Criterion 6: Coupon is published (not draft/pending) (0 points but affects pass)
    coupon_status = coupon.get('status', '')
    status_published = coupon_status.strip().lower() == 'publish'
    if coupon_found:
        if status_published:
            feedback_parts.append("Coupon status: published")
        else:
            feedback_parts.append(f"Coupon status NOT published: '{coupon_status}' (draft coupons are not active)")

    # Criterion 7: Minimum spend matches (10 points)
    minimum_amount = coupon.get('minimum_amount', '')
    min_spend_correct = False
    if minimum_amount:
        try:
            actual_min = float(minimum_amount)
            expected_min = float(expected_min_spend)
            if abs(actual_min - expected_min) < 0.01:
                score += 10
                min_spend_correct = True
                feedback_parts.append(f"Minimum spend correct: ${expected_min_spend}")
            else:
                feedback_parts.append(f"Minimum spend mismatch: expected ${expected_min_spend}, got ${minimum_amount}")
        except (ValueError, TypeError):
            feedback_parts.append(f"Minimum spend invalid: '{minimum_amount}'")
    else:
        feedback_parts.append("Minimum spend not set")

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
                form_visible = process_result.get('coupon_form_visible', False)

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
        if coupon_found and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: DB coupon + VLM workflow agree")
            details['cross_validation'] = 'pass'
        elif coupon_found and not vlm_workflow_confirmed:
            feedback_parts.append("Cross-validation mismatch: coupon in DB but workflow not confirmed by VLM")
            details['cross_validation'] = 'mismatch'
        elif vlm_workflow_confirmed and not coupon_found:
            score += 2
            feedback_parts.append("Cross-validation: VLM sees workflow but coupon not in DB")
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'

    else:
        # VLM not available — no free points, just note it
        feedback_parts.append("VLM checks skipped (unavailable)")

    # ================================================================
    # PASS CRITERIA
    # ================================================================

    # Must have coupon found AND published AND score >= 55
    # When VLM is available, must also have VLM confirmation
    if vlm_available:
        passed = score >= 55 and coupon_found and status_published and vlm_workflow_confirmed
    else:
        passed = score >= 55 and coupon_found and status_published

    details.update({
        "coupon_found": coupon_found,
        "newly_created": newly_created,
        "code_correct": code_correct,
        "type_correct": type_correct,
        "amount_correct": amount_correct,
        "usage_limit_correct": usage_limit_correct,
        "min_spend_correct": min_spend_correct,
        "status_published": status_published,
        "vlm_available": vlm_available,
        "vlm_workflow_confirmed": vlm_workflow_confirmed,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
