#!/usr/bin/env python3
"""
Verifier for optimize_url_structure task.

Verification Strategy (Hybrid):
1. Programmatic (80 pts): Check WordPress database options for exact string matches.
   - Category base == 'collection'
   - Tag base == 'labeled'
   - Product base contains '/shop/' and '%product_cat%'
2. VLM Trajectory (20 pts): Verify the agent navigated to the Settings > Permalinks page.

Anti-gaming:
- Checks if settings actually changed from initial state.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ================================================================
# VLM PROMPTS
# ================================================================

TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent configuring WordPress Permalink settings.

The goal is to navigate to "Settings > Permalinks" and modify URL structures.

Look at the sequence of images and determine:
1. Did the agent navigate to the "Permalinks" settings page? (Look for "Permalink Settings" heading, "Common Settings", "Product permalinks")
2. Did the agent interact with the "Optional" section (Category base, Tag base)?
3. Did the agent interact with the "Product permalinks" radio buttons?
4. Did the agent click "Save Changes"?

Respond in JSON format:
{
    "permalinks_page_reached": true/false,
    "settings_modified": true/false,
    "save_clicked": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

# ================================================================
# VERIFIER
# ================================================================

def verify_optimize_url_structure(traj, env_info, task_info):
    """
    Verify SEO URL structure configuration.
    """
    # 1. Setup & Data Extraction
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm') 
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata expectations
    metadata = task_info.get('metadata', {})
    exp_cat_base = metadata.get('expected_category_base', 'collection')
    exp_tag_base = metadata.get('expected_tag_base', 'labeled')
    exp_prod_part1 = metadata.get('expected_product_structure_part_1', '/shop/')
    exp_prod_part2 = metadata.get('expected_product_structure_part_2', '%product_cat%')

    # Load result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    final_settings = result.get('final_settings', {})
    if not final_settings:
         return {"passed": False, "score": 0, "feedback": "Final settings were empty or could not be retrieved."}

    # 2. Programmatic Scoring (80 pts)
    score = 0
    feedback_parts = []
    
    # Check if anything changed (Anti-gaming)
    if not result.get('settings_changed', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Settings were not changed from the initial default state."
        }

    # Check Category Base (30 pts)
    act_cat_base = final_settings.get('category_base', '')
    if act_cat_base == exp_cat_base:
        score += 30
        feedback_parts.append("Category base correct")
    else:
        feedback_parts.append(f"Category base incorrect (found: '{act_cat_base}', expected: '{exp_cat_base}')")

    # Check Tag Base (30 pts)
    act_tag_base = final_settings.get('tag_base', '')
    if act_tag_base == exp_tag_base:
        score += 30
        feedback_parts.append("Tag base correct")
    else:
        feedback_parts.append(f"Tag base incorrect (found: '{act_tag_base}', expected: '{exp_tag_base}')")

    # Check Product Structure (20 pts)
    # The stored value might look like "/shop/%product_cat%/" or similar
    act_prod_base = final_settings.get('product_base', '')
    if exp_prod_part1 in act_prod_base and exp_prod_part2 in act_prod_base:
        score += 20
        feedback_parts.append("Product structure correct")
    else:
        feedback_parts.append(f"Product structure incorrect (found: '{act_prod_base}')")

    # 3. VLM Verification (20 pts)
    # Only verify if we have partial programmatic success to save resources
    vlm_score = 0
    if score >= 30 and query_vlm:
        # Sample frames from trajectory
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=6)
        
        try:
            vlm_res = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("permalinks_page_reached"):
                    vlm_score += 10
                if parsed.get("save_clicked"):
                    vlm_score += 10
                
                if vlm_score > 0:
                    feedback_parts.append(f"VLM verified workflow (+{vlm_score} pts)")
            else:
                logger.warning(f"VLM query failed: {vlm_res.get('error')}")
                # Fallback: if score is high (perfect programmatic), give benefit of doubt
                if score == 80:
                    vlm_score = 20
        except Exception as e:
            logger.error(f"VLM exception: {e}")
            if score == 80:
                vlm_score = 20
    elif score == 80:
         # If VLM unavailable but programmatic is perfect
         vlm_score = 20

    score += vlm_score

    # 4. Final Result
    # Must get 100% of programmatic checks + reasonable VLM or just perfect programmatic
    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }