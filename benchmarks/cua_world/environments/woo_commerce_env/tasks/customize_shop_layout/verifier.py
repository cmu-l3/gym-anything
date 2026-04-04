#!/usr/bin/env python3
"""
Verifier for Customize Shop Layout task.

Task: Configure WooCommerce Product Catalog settings via Customizer.
- Shop page display: 'both' (categories & products)
- Default sorting: 'price-desc' (High to Low)
- Products per row: 3
- Rows per page: 5

Verification Strategy:
1. Programmatic (80 points): Check `wp_options` for correct values.
2. VLM (20 points): Verify agent used the Customizer UI (trajectory analysis).

Pass Threshold: 100 points (all settings must be correct).
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

TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent configuring a website.

Look for the "WordPress Customizer" interface. It typically has:
- A sidebar on the left with a menu (e.g., "WooCommerce", "Product Catalog").
- A preview of the website on the right.

Did the agent:
1. Open the "WooCommerce" section in the sidebar?
2. Open the "Product Catalog" subsection?
3. Adjust settings like "Products per row", "Rows per page", or "Shop page display"?

Respond in JSON:
{
    "customizer_opened": true/false,
    "product_catalog_settings_visible": true/false,
    "settings_adjusted": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def verify_customize_shop_layout(traj, env_info, task_info):
    """
    Verify shop layout customization.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values from metadata
    metadata = task_info.get('metadata', {})
    exp_display = metadata.get('expected_display_mode', 'both')
    exp_orderby = metadata.get('expected_orderby', 'price-desc')
    exp_cols = metadata.get('expected_columns', '3')
    exp_rows = metadata.get('expected_rows', '5')

    # Load result
    result = {}
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    current = result.get('current_config', {})
    
    score = 0
    feedback = []

    # 1. Verify Display Mode (20 pts)
    # Note: Empty string check handles weird WP behavior where default might be returned as empty
    # But for 'both', it must be explicit.
    val_display = current.get('display_mode', '')
    if val_display == exp_display:
        score += 20
        feedback.append("Display mode correct (both)")
    else:
        feedback.append(f"Display mode incorrect (found: '{val_display}', expected: '{exp_display}')")

    # 2. Verify Sorting (20 pts)
    val_orderby = current.get('orderby', '')
    if val_orderby == exp_orderby:
        score += 20
        feedback.append("Default sorting correct (price-desc)")
    else:
        feedback.append(f"Sorting incorrect (found: '{val_orderby}', expected: '{exp_orderby}')")

    # 3. Verify Columns (20 pts)
    val_cols = str(current.get('columns', ''))
    if val_cols == exp_cols:
        score += 20
        feedback.append("Column count correct (3)")
    else:
        feedback.append(f"Columns incorrect (found: '{val_cols}', expected: '{exp_cols}')")

    # 4. Verify Rows (20 pts)
    val_rows = str(current.get('rows', ''))
    if val_rows == exp_rows:
        score += 20
        feedback.append("Row count correct (5)")
    else:
        feedback.append(f"Rows incorrect (found: '{val_rows}', expected: '{exp_rows}')")

    # 5. VLM Verification (20 pts)
    # Check if they actually used the customizer UI
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        
        if vlm_res:
            vlm_score = 0
            if vlm_res.get('customizer_opened'): vlm_score += 5
            if vlm_res.get('product_catalog_settings_visible'): vlm_score += 10
            if vlm_res.get('settings_adjusted'): vlm_score += 5
            
            score += vlm_score
            if vlm_score > 0:
                feedback.append(f"VLM confirmed Customizer usage (+{vlm_score} pts)")
        else:
            # If VLM fails, give benefit of doubt if settings are correct
            if score == 80:
                score += 20
                feedback.append("VLM unavailable, awarding UI points based on correct state")
    else:
        # No VLM available
        if score == 80:
            score += 20
            feedback.append("VLM unavailable, awarding UI points based on correct state")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }