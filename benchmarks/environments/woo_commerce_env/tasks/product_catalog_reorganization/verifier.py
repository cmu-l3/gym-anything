#!/usr/bin/env python3
"""
Verifier for Product Catalog Reorganization task in WooCommerce.

This is a very_hard task requiring the agent to:
1. Create category hierarchy (parent + 2 subcategories)
2. Assign products to subcategories
3. Create and assign product tags
4. Set products as Featured
5. Update a product short description

Verification Strategy (Hybrid: Programmatic + VLM):

Programmatic checks (70 points):
  1. Parent category 'Outdoor & Recreation' exists (8 pts)
  2. 'Camping Gear' subcategory exists under parent (8 pts)
  3. 'Fitness Equipment' subcategory exists under parent (8 pts)
  4. Products assigned to correct subcategories (12 pts: 4 each for 3 products)
  5. Tags exist (6 pts: 2 each for 3 tags)
  6. Tags assigned to correct products (12 pts: 2 each for 6 assignments)
  7. Featured products set correctly (8 pts: 4 each for 2 products)
  8. Short description correct (8 pts)

VLM checks (30 points):
  9. Process verification (15 pts)
  10. Final state verification (10 pts)
  11. Cross-validation (5 pts)

Pass threshold: 50 points AND parent category exists AND at least 1 subcategory exists AND
at least 2 products correctly categorized
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent reorganizing a WooCommerce product catalog via the WordPress admin interface.

The images are sampled chronologically (earliest to latest).

For successful catalog reorganization, the agent should:
1. Navigate to Products > Categories to create parent/child categories
2. Edit individual products to assign categories, tags, and featured status
3. Update product descriptions
4. Save changes across multiple products

Assess:
1. WORKFLOW_COMPLETED: Did the agent work across product categories, tags, and individual product editing?
2. CATEGORY_MANAGEMENT: Did the agent visit the categories management page?
3. PRODUCT_EDITING: Did the agent edit multiple individual products?
4. MULTI_PRODUCT_PROGRESSION: Do frames show the agent working on different products?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "category_management": true/false,
    "product_editing": true/false,
    "multi_product_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WooCommerce catalog reorganization task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress/WooCommerce admin interface visible?
2. SUCCESS_INDICATORS: Are there success indicators (product updated, category created)?
3. PRODUCT_OR_CATEGORY_PAGE: Is a product editing or category management page visible?
4. ERROR_INDICATORS: Are there error messages?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "product_or_category_page": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_product_catalog_reorganization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_desc = metadata.get('short_description_update', {}).get(
        'text', 'Ultralight double hammock perfect for backpacking and outdoor adventures. Supports up to 500 lbs.')

    feedback_parts = []
    score = 0
    details = {}

    # Load result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/product_catalog_reorg_result.json", temp_result.name)
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

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # 1. Parent category exists (8 pts)
    parent_exists = result.get('parent_category_exists', False)
    if parent_exists:
        score += 8
        feedback_parts.append("Parent category 'Outdoor & Recreation' exists")
    else:
        feedback_parts.append("Parent category 'Outdoor & Recreation' NOT found")

    # 2. Camping Gear subcategory (8 pts)
    camping = result.get('camping_gear', {})
    camping_exists = camping.get('exists', False)
    camping_is_child = camping.get('is_child_of_parent', False)
    subcats_ok = 0

    if camping_exists and camping_is_child:
        score += 8
        subcats_ok += 1
        feedback_parts.append("'Camping Gear' subcategory correctly under parent")
    elif camping_exists:
        score += 4
        subcats_ok += 1
        feedback_parts.append("'Camping Gear' exists but not under correct parent")
    else:
        feedback_parts.append("'Camping Gear' NOT found")

    # 3. Fitness Equipment subcategory (8 pts)
    fitness = result.get('fitness_equipment', {})
    fitness_exists = fitness.get('exists', False)
    fitness_is_child = fitness.get('is_child_of_parent', False)

    if fitness_exists and fitness_is_child:
        score += 8
        subcats_ok += 1
        feedback_parts.append("'Fitness Equipment' subcategory correctly under parent")
    elif fitness_exists:
        score += 4
        subcats_ok += 1
        feedback_parts.append("'Fitness Equipment' exists but not under correct parent")
    else:
        feedback_parts.append("'Fitness Equipment' NOT found")

    # 4. Product category assignments (12 pts: 4 each)
    assignments = result.get('category_assignments', {})
    products_correctly_categorized = 0

    for key, label in [('pch_in_camping', 'Camping Hammock in Camping Gear'),
                       ('ymp_in_fitness', 'Yoga Mat in Fitness Equipment'),
                       ('rbs_in_fitness', 'Resistance Bands in Fitness Equipment')]:
        if assignments.get(key, False):
            score += 4
            products_correctly_categorized += 1
            feedback_parts.append(f"{label}: correct")
        else:
            feedback_parts.append(f"{label}: NOT assigned")

    # 5. Tags exist (6 pts: 2 each)
    tags = result.get('tags', {})
    tags_exist_count = 0

    for key, name in [('bestseller_exists', 'bestseller'),
                      ('ecofriendly_exists', 'eco-friendly'),
                      ('giftidea_exists', 'gift-idea')]:
        if tags.get(key, False):
            score += 2
            tags_exist_count += 1
            feedback_parts.append(f"Tag '{name}' exists")
        else:
            feedback_parts.append(f"Tag '{name}' NOT found")

    # 6. Tag assignments (12 pts: 2 each for 6 assignments)
    tag_assigns = result.get('tag_assignments', {})
    tag_assigns_correct = 0

    assignment_labels = {
        'bestseller_wbh': 'bestseller→Headphones',
        'bestseller_ymp': 'bestseller→Yoga Mat',
        'ecofriendly_oct': 'eco-friendly→T-Shirt',
        'ecofriendly_bcb': 'eco-friendly→Cutting Board',
        'giftidea_led': 'gift-idea→Desk Lamp',
        'giftidea_cpp': 'gift-idea→Plant Pot',
    }

    for key, label in assignment_labels.items():
        if tag_assigns.get(key, False):
            score += 2
            tag_assigns_correct += 1
            feedback_parts.append(f"Tag {label}: assigned")
        else:
            feedback_parts.append(f"Tag {label}: NOT assigned")

    # 7. Featured products (8 pts: 4 each)
    featured = result.get('featured', {})
    featured_count = 0

    if featured.get('wbh_featured', False):
        score += 4
        featured_count += 1
        feedback_parts.append("Headphones: featured")
    else:
        feedback_parts.append("Headphones: NOT featured")

    if featured.get('ymp_featured', False):
        score += 4
        featured_count += 1
        feedback_parts.append("Yoga Mat: featured")
    else:
        feedback_parts.append("Yoga Mat: NOT featured")

    # 8. Short description (8 pts)
    short_desc = result.get('short_description', '')
    desc_correct = False

    if short_desc:
        # Normalize whitespace for comparison
        actual_normalized = ' '.join(short_desc.strip().split())
        expected_normalized = ' '.join(expected_desc.strip().split())

        if actual_normalized.lower() == expected_normalized.lower():
            score += 8
            desc_correct = True
            feedback_parts.append("Short description: exact match")
        elif 'ultralight' in actual_normalized.lower() and '500' in actual_normalized:
            score += 5
            desc_correct = True
            feedback_parts.append("Short description: close match (key terms present)")
        elif 'hammock' in actual_normalized.lower():
            score += 2
            feedback_parts.append("Short description: partial match")
        else:
            feedback_parts.append(f"Short description: wrong content")
    else:
        feedback_parts.append("Short description: empty")

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
                cat_mgmt = process_result.get('category_management', False)
                product_edit = process_result.get('product_editing', False)
                multi_product = process_result.get('multi_product_progression', False)
                if workflow_ok and (cat_mgmt or multi_product):
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Catalog reorganization workflow confirmed")
                elif workflow_ok or product_edit:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Product editing workflow confirmed")
                elif cat_mgmt:
                    score += 5
                    feedback_parts.append("VLM process: Category management seen")
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
                    feedback_parts.append("VLM final: Admin visible")

        if parent_exists and products_correctly_categorized > 0 and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: Categories + products + VLM agree")
            details['cross_validation'] = 'pass'
        else:
            details['cross_validation'] = 'partial' if vlm_workflow_confirmed else 'neither'
    else:
        feedback_parts.append("VLM checks skipped (unavailable)")

    # ================================================================
    # PASS CRITERIA
    # ================================================================
    min_subcats = subcats_ok >= 1
    min_products = products_correctly_categorized >= 2

    if vlm_available:
        passed = score >= 50 and parent_exists and min_subcats and min_products and vlm_workflow_confirmed
    else:
        passed = score >= 50 and parent_exists and min_subcats and min_products

    details.update({
        "parent_exists": parent_exists,
        "subcats_ok": subcats_ok,
        "products_correctly_categorized": products_correctly_categorized,
        "tags_exist_count": tags_exist_count,
        "tag_assigns_correct": tag_assigns_correct,
        "featured_count": featured_count,
        "desc_correct": desc_correct,
        "vlm_available": vlm_available,
        "vlm_workflow_confirmed": vlm_workflow_confirmed,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
