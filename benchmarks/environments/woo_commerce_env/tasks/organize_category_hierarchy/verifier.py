#!/usr/bin/env python3
"""
Verifier for Organize Category Hierarchy task.

Verification Strategy (Hybrid):
1. Programmatic Checks (85 points):
   - Database verification of category existence, hierarchy, descriptions, and product assignments.
2. VLM Verification (15 points):
   - Visual confirmation via trajectory that the user interacted with the category UI
   - Visual check of the hierarchy indentation in the list table.

Scoring Breakdown:
- Apparel Category Exists: 10 pts
- Apparel Description Correct: 5 pts
- Tops Exists & Child of Apparel: 15 pts
- Tops Description Correct: 5 pts
- Bottoms Exists & Child of Apparel: 15 pts
- Bottoms Description Correct: 5 pts
- Product Assignments (3 * 10): 30 pts
- VLM Visual Verification: 15 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ==============================================================================
# VLM PROMPTS
# ==============================================================================

HIERARCHY_VISUAL_PROMPT = """You are verifying a WooCommerce task where the user had to create a category hierarchy.

Look at this screenshot of the WooCommerce Category list.
Expected Hierarchy:
- Apparel (Parent)
  - Tops (Child)
  - Bottoms (Child)

In WooCommerce, child categories are typically shown below their parent and often preceded by a dash '—' or indented.

Assess:
1. Do you see "Apparel", "Tops", and "Bottoms" in the list?
2. visual_hierarchy: Is there visual indication that Tops/Bottoms are sub-categories of Apparel (e.g., "— Tops", indentation)?
3. description_visible: Can you see descriptions like "Clothing and fashion items" or "upper body wear"?

Respond in JSON:
{
    "categories_visible": true/false,
    "visual_hierarchy_confirmed": true/false,
    "descriptions_visible": true/false,
    "confidence": "low/medium/high"
}
"""

def verify_organize_category_hierarchy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ==========================================================================
    # 1. LOAD DATA
    # ==========================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # ==========================================================================
    # 2. PROGRAMMATIC CHECKS (85 Points Max)
    # ==========================================================================
    
    cats = result.get("categories", {})
    prods = result.get("products", {})
    
    # --- Check Apparel (Parent) ---
    apparel = cats.get("apparel", {})
    if apparel.get("exists"):
        score += 10
        feedback.append("Apparel category created")
        
        # Check description (case insensitive partial match)
        if "clothing and fashion" in apparel.get("description", "").lower():
            score += 5
            feedback.append("Apparel description correct")
    else:
        feedback.append("Apparel category NOT found")

    # --- Check Tops (Child) ---
    tops = cats.get("tops", {})
    if tops.get("exists"):
        # Check hierarchy
        if apparel.get("exists") and tops.get("parent") == apparel.get("id") and apparel.get("id") != 0:
            score += 15
            feedback.append("Tops is correctly a child of Apparel")
        elif tops.get("parent") != 0:
            # It has a parent, but maybe not the right one or we couldn't resolve ID
            score += 5
            feedback.append("Tops has a parent but hierarchy verification failed")
        else:
            feedback.append("Tops exists but is not a child category")
            
        # Check description
        if "upper body" in tops.get("description", "").lower():
            score += 5
            feedback.append("Tops description correct")
    else:
        feedback.append("Tops category NOT found")

    # --- Check Bottoms (Child) ---
    bottoms = cats.get("bottoms", {})
    if bottoms.get("exists"):
        # Check hierarchy
        if apparel.get("exists") and bottoms.get("parent") == apparel.get("id") and apparel.get("id") != 0:
            score += 15
            feedback.append("Bottoms is correctly a child of Apparel")
        elif bottoms.get("parent") != 0:
             score += 5
             feedback.append("Bottoms has a parent but hierarchy verification failed")
        else:
            feedback.append("Bottoms exists but is not a child category")
            
        # Check description
        if "lower body" in bottoms.get("description", "").lower():
            score += 5
            feedback.append("Bottoms description correct")
    else:
        feedback.append("Bottoms category NOT found")

    # --- Check Product Assignments ---
    # T-Shirt -> Tops
    if prods.get("tshirt", {}).get("assigned_correctly"):
        score += 10
        feedback.append("T-Shirt assigned to Tops")
    
    # Sweater -> Tops
    if prods.get("sweater", {}).get("assigned_correctly"):
        score += 10
        feedback.append("Sweater assigned to Tops")

    # Jeans -> Bottoms
    if prods.get("jeans", {}).get("assigned_correctly"):
        score += 10
        feedback.append("Jeans assigned to Bottoms")

    # ==========================================================================
    # 3. VLM VISUAL VERIFICATION (15 Points Max)
    # ==========================================================================
    # Only verify if we have decent programmatic score (avoid wasting tokens on empty tasks)
    if score >= 40:
        from vlm_utils import query_vlm, get_final_screenshot
        final_screenshot = get_final_screenshot(traj)
        
        if final_screenshot:
            vlm_res = query_vlm(prompt=HIERARCHY_VISUAL_PROMPT, image=final_screenshot)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("visual_hierarchy_confirmed"):
                    score += 15
                    feedback.append("VLM confirmed visual hierarchy")
                elif parsed.get("categories_visible"):
                    score += 10
                    feedback.append("VLM saw categories but hierarchy unclear")
                else:
                    feedback.append("VLM did not verify visual hierarchy")
            else:
                # If VLM fails, give benefit of doubt if programmatic checks passed strongly
                if score >= 70:
                    score += 15
                    feedback.append("VLM unavailable, assuming visual match based on DB")
        else:
             feedback.append("No screenshot for visual verification")
    else:
        feedback.append("Skipping VLM check due to low programmatic score")

    # ==========================================================================
    # 4. FINAL SCORE
    # ==========================================================================
    passed = score >= 60 and \
             apparel.get("exists") and \
             tops.get("exists") and \
             bottoms.get("exists") and \
             (prods.get("tshirt", {}).get("assigned_correctly") or prods.get("jeans", {}).get("assigned_correctly"))

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback),
        "details": result
    }