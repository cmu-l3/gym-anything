#!/usr/bin/env python3
"""
Verifier for implement_shoppable_editorial_content task.

Checks:
1. Content Type 'editorial_review' creation.
2. Field 'field_merchandise' creation and configuration (Entity Reference -> Product).
3. Display settings (Rendered Entity, Teaser view mode).
4. Content creation (Node exists, published, references correct product).
5. Visual verification using VLM (checking for embedded product/cart button).
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_shoppable_content(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read programmatic evidence
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Programmatic Verification (80 points total)
    # ---------------------------------------------------------

    # 1. Content Type Created (15 pts)
    if str(result.get('content_type_exists', '0')) == '1':
        score += 15
        feedback_parts.append("Content type 'editorial_review' exists.")
    else:
        feedback_parts.append("Content type 'editorial_review' NOT found.")

    # 2. Field Created & Configured (20 pts)
    field_exists = str(result.get('field_exists', 'false')).lower() == 'true'
    type_correct = str(result.get('field_type_correct', 'false')).lower() == 'true'
    target_correct = str(result.get('target_type_correct', 'false')).lower() == 'true'
    
    if field_exists:
        if type_correct and target_correct:
            score += 20
            feedback_parts.append("Field 'Merchandise' correctly configured as Product Reference.")
        else:
            score += 10
            feedback_parts.append("Field 'Merchandise' exists but has wrong type or target.")
    else:
        feedback_parts.append("Field 'Merchandise' NOT found.")

    # 3. Display Settings (25 pts)
    in_display = str(result.get('field_in_display', 'false')).lower() == 'true'
    formatter = result.get('display_formatter', '')
    view_mode = result.get('display_view_mode', '')

    if in_display:
        if formatter == 'entity_reference_entity_view':
            score += 15
            feedback_parts.append("Display set to 'Rendered entity'.")
            if view_mode == 'teaser':
                score += 10
                feedback_parts.append("View mode set to 'Teaser'.")
            else:
                feedback_parts.append(f"View mode is '{view_mode}' (expected 'Teaser').")
        else:
            score += 5
            feedback_parts.append(f"Field is in display but formatter is '{formatter}' (expected 'Rendered entity').")
    else:
        feedback_parts.append("Field 'Merchandise' is disabled in Manage Display.")

    # 4. Content Created (20 pts)
    node_created = str(result.get('node_created', 'false')).lower() == 'true'
    status = str(result.get('node_status', '0'))
    ref_correct = str(result.get('referenced_product_correct', 'false')).lower() == 'true'

    if node_created:
        score += 5
        feedback_parts.append("Editorial Review node created.")
        if status == '1':
            score += 5
            feedback_parts.append("Node is published.")
        else:
            feedback_parts.append("Node is not published.")
            
        if ref_correct:
            score += 10
            feedback_parts.append("Correctly referenced 'Sony WH-1000XM5'.")
        else:
            feedback_parts.append("Referenced product is incorrect or missing.")
    else:
        feedback_parts.append("No 'Editorial Review' content created.")

    # ---------------------------------------------------------
    # VLM Verification (20 points total)
    # ---------------------------------------------------------
    # We look for the visual result: A product teaser inside the node page.
    # The teaser typically shows the product image and an "Add to Cart" button.
    
    final_img = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_img:
        prompt = """
        Analyze this screenshot of a Drupal website.
        1. Is there an article or review visible (Look for a title like "Sony... Deep Dive")?
        2. Is there a product embedded IN the content? Look for a product image, price, and an 'Add to Cart' button appearing *within* the main content area (not just a sidebar).
        
        Answer JSON: {"review_visible": bool, "product_embedded": bool, "add_to_cart_visible": bool}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, image=final_img)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('review_visible', False):
                vlm_score += 5
            if parsed.get('product_embedded', False) and parsed.get('add_to_cart_visible', False):
                vlm_score += 15
                feedback_parts.append("VLM confirmed shoppable product embedded in content.")
            elif parsed.get('product_embedded', False):
                vlm_score += 10
                feedback_parts.append("VLM saw product, but 'Add to Cart' might be missing.")
            else:
                feedback_parts.append("VLM did not see embedded product.")
                
        except Exception as e:
            logger.error(f"VLM error: {e}")
            # Fallback: if programmatic score is high, assume visual is okay-ish to avoid failing on VLM error
            if score >= 70:
                vlm_score = 10 
    
    score += vlm_score

    # Normalize score
    score = min(100, score)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }