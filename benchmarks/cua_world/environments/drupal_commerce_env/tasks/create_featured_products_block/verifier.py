#!/usr/bin/env python3
"""
Verifier for create_featured_products_block task.

Scoring Breakdown (100 pts):
1. Product Data (30 pts):
   - 10 pts for each target product correctly promoted (Sony, Apple, Canon).
   - Penalty if non-target (Logitech) is promoted.
2. View Configuration (40 pts):
   - 10 pts: View exists
   - 10 pts: Filter by 'Promoted to front page'
   - 10 pts: Sort by 'Authored on' (Desc)
   - 10 pts: Pager set to 3 items
3. Block Placement (30 pts):
   - 10 pts: Block exists
   - 10 pts: Region is 'content'
   - 10 pts: Theme is 'olivero' (or default)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_featured_products_block(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # ------------------------------------------------------------------
    # 1. Load exported data
    # ------------------------------------------------------------------
    try:
        # Load main result
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            copy_from_env("/tmp/task_result.json", f.name)
            with open(f.name, 'r') as json_f:
                result = json.load(json_f)
            os.unlink(f.name)

        # Load View config
        view_config = {}
        if result.get("view_exists"):
            with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
                copy_from_env("/tmp/view_config.json", f.name)
                with open(f.name, 'r') as json_f:
                    # Sometimes drush outputs weird stuff, handle empty
                    try:
                        view_config = json.load(json_f)
                    except:
                        pass
                os.unlink(f.name)

        # Load Block config
        block_config = {}
        if result.get("block_exists"):
            with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
                copy_from_env("/tmp/block_config.json", f.name)
                with open(f.name, 'r') as json_f:
                    try:
                        block_config = json.load(json_f)
                    except:
                        pass
                os.unlink(f.name)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading verification data: {str(e)}"}

    # ------------------------------------------------------------------
    # 2. Verify Product Data (30 pts)
    # ------------------------------------------------------------------
    products = result.get("product_data", {})
    
    # Check Targets
    targets_met = 0
    if products.get("sony_promoted") == 1: targets_met += 1
    if products.get("apple_promoted") == 1: targets_met += 1
    if products.get("canon_promoted") == 1: targets_met += 1
    
    product_score = targets_met * 10
    feedback.append(f"Product Data: {targets_met}/3 target products promoted.")

    # Check Non-Target
    if products.get("logi_promoted") == 1:
        product_score = max(0, product_score - 5)
        feedback.append("Penalty: Non-target product (Logitech) was incorrectly promoted.")

    score += product_score

    # ------------------------------------------------------------------
    # 3. Verify View Configuration (40 pts)
    # ------------------------------------------------------------------
    view_score = 0
    if result.get("view_exists"):
        view_score += 10
        feedback.append("View: 'staff_picks' exists.")
        
        # Helper to traverse nested dicts safely
        display = view_config.get("display", {}).get("default", {}).get("display_options", {})
        
        # Check Filters (Promoted = True)
        filters = display.get("filters", {})
        has_promote_filter = False
        for key, val in filters.items():
            if val.get("field") == "promote" and val.get("value") in ["1", 1, "True", True]:
                has_promote_filter = True
                break
        
        if has_promote_filter:
            view_score += 10
            feedback.append("View: Correctly filters by 'Promoted to front page'.")
        else:
            feedback.append("View: Missing or incorrect 'Promoted' filter.")

        # Check Sort (Created/Authored On Desc)
        sorts = display.get("sorts", {})
        has_sort = False
        for key, val in sorts.items():
            # Usually 'created' or 'authored_on'
            if val.get("field") == "created" and val.get("order", "").lower() == "desc":
                has_sort = True
                break
        
        if has_sort:
            view_score += 10
            feedback.append("View: Correctly sorts by Newest first.")
        else:
            feedback.append("View: Missing or incorrect Sort criteria.")

        # Check Pager (Items = 3)
        pager = display.get("pager", {}).get("options", {})
        if str(pager.get("items_per_page")) == "3":
            view_score += 10
            feedback.append("View: Pager correctly set to 3 items.")
        else:
            items = pager.get("items_per_page", "unknown")
            feedback.append(f"View: Pager set to {items} (expected 3).")
            
    else:
        feedback.append("View: 'staff_picks' not found.")

    score += view_score

    # ------------------------------------------------------------------
    # 4. Verify Block Placement (30 pts)
    # ------------------------------------------------------------------
    block_score = 0
    if result.get("block_exists"):
        block_score += 10
        feedback.append("Block: Block placement found.")
        
        if block_config.get("theme") == "olivero":
            block_score += 10
            feedback.append("Block: Assigned to 'olivero' theme.")
        else:
            feedback.append(f"Block: Assigned to wrong theme ({block_config.get('theme')}).")

        if block_config.get("region") == "content":
            block_score += 10
            feedback.append("Block: Placed in 'content' region.")
        else:
            feedback.append(f"Block: Placed in wrong region ({block_config.get('region')}).")
            
    else:
        feedback.append("Block: Not placed in layout.")

    score += block_score

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = (score >= 70) and result.get("view_exists") and result.get("block_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }