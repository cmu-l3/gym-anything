#!/usr/bin/env python3
"""
Verifier for Grant Manual Download Access task in WooCommerce.

Verification Strategy:
1. Programmatic Checks (80 points):
   - Digital product created correctly (Virtual, Downloadable, File path set)
   - Physical product created correctly (Not Downloadable)
   - Order created with Physical product ONLY (Anti-gaming check: Agent shouldn't just sell the digital item)
   - Permission record exists linking Order ID + Digital Product ID
   - Downloads remaining set to 5

2. VLM Checks (20 points):
   - Trajectory verification of the "Downloadable Product Permissions" meta box interaction.
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
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

TRAJECTORY_PROMPT = """You are analyzing screenshots of a WooCommerce admin task.
The user is supposed to manually grant download access to a file on an existing order.

Look for:
1. Navigation to an Order Edit page.
2. Interaction with a meta box labeled "Downloadable Product Permissions" (usually at the bottom).
3. Searching for a product in that permissions box (e.g., "Exclusive Digital Supplement").
4. Setting a "Downloads remaining" value (specifically 5).
5. Saving the order.

Respond in JSON:
{
    "permissions_box_visible": true/false,
    "product_search_visible": true/false,
    "downloads_remaining_set": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_grant_manual_download_access(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # 1. Check Digital Product (15 pts)
    dig_prod = result.get('digital_product', {})
    if dig_prod.get('found'):
        if dig_prod.get('is_virtual') == 'yes' and dig_prod.get('is_downloadable') == 'yes':
            score += 10
            feedback.append("Digital product configured correctly.")
        else:
            score += 5
            feedback.append("Digital product found but missing Virtual/Downloadable flags.")
        
        if dig_prod.get('has_file_path'):
            score += 5
            feedback.append("Digital product has file path.")
    else:
        feedback.append("Digital product 'Exclusive Digital Supplement' not found.")

    # 2. Check Physical Product (10 pts)
    phys_prod = result.get('physical_product', {})
    if phys_prod.get('found'):
        if phys_prod.get('is_downloadable') == 'no':
            score += 10
            feedback.append("Physical product configured correctly.")
        else:
            score += 5
            feedback.append("Physical product found but incorrectly marked downloadable.")
    else:
        feedback.append("Physical product 'Physical Training Manual' not found.")

    # 3. Check Order Structure (35 pts)
    order = result.get('order', {})
    if order.get('found'):
        score += 10
        feedback.append("Order found.")
        
        if order.get('status') == 'wc-completed':
            score += 5
            feedback.append("Order status is Completed.")
        
        if order.get('contains_physical_item'):
            score += 10
            feedback.append("Order contains correct physical item.")
            
        # Anti-gaming: Ensure they didn't just add the digital item as a line item
        if not order.get('contains_digital_item_line'):
            score += 10
            feedback.append("Correctly granted permission WITHOUT adding digital line item.")
        else:
            feedback.append("Anti-gaming Fail: You added the digital product as a line item instead of granting permission manually.")
    else:
        feedback.append("Target order not found.")

    # 4. Check Permissions (20 pts)
    perm = result.get('permission', {})
    if perm.get('granted'):
        score += 10
        feedback.append("Download permission record found.")
        
        if str(perm.get('downloads_remaining')) == '5':
            score += 10
            feedback.append("Downloads remaining set correctly to 5.")
        else:
            feedback.append(f"Downloads remaining was {perm.get('downloads_remaining')}, expected 5.")
    else:
        feedback.append("No download permission granted.")

    # 5. VLM Check (20 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=5)
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        if vlm_res:
            if vlm_res.get('permissions_box_visible'):
                score += 10
            if vlm_res.get('downloads_remaining_set'):
                score += 10
            feedback.append(f"VLM Analysis: {json.dumps(vlm_res)}")
    else:
        # If no VLM, grant points if programmatic passed (assume valid workflow)
        if score >= 60:
            score += 20
            feedback.append("VLM unavailable - points awarded based on result.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }