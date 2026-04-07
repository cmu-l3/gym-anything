#!/usr/bin/env python3
"""
Verifier for create_defects_by_product_report task.

Criteria:
1. Filter Existence: An `ir.filters` record named "Alerts by Product" exists for `quality.alert`.
2. Configuration: The filter's context includes grouping by product (`product_id` or `product_tmpl_id`).
3. VLM Verification: The final screenshot shows the Pivot view active.
"""

import json
import os
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_defects_by_product_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Filter Existence (40 pts)
    if result.get("filter_found"):
        score += 40
        feedback_parts.append("Filter 'Alerts by Product' found.")
    else:
        feedback_parts.append("Filter 'Alerts by Product' NOT found.")
        return {"passed": False, "score": 0, "feedback": "Required filter not found."}

    # 2. Check Grouping Configuration (40 pts)
    # The context string should look like "{'group_by': ['product_id']}"
    context_str = result.get("filter_context", "").replace("'", '"')
    
    # Allow for product_id (variant) or product_tmpl_id (template)
    group_by_correct = False
    if "group_by" in context_str:
        if "product_id" in context_str or "product_tmpl_id" in context_str:
            group_by_correct = True
    
    if group_by_correct:
        score += 40
        feedback_parts.append("Filter correctly groups by Product.")
    else:
        feedback_parts.append(f"Filter has incorrect grouping. Context: {result.get('filter_context')}")

    # 3. VLM Verification (20 pts)
    # Verify the screenshot shows a Pivot view (grid)
    final_screenshot = get_final_screenshot(traj)
    vlm_score = 0
    
    if final_screenshot:
        prompt = """
        Analyze this screenshot of Odoo.
        1. Is the view in 'Pivot' mode? (Look for a grid/table with collapsible rows and numeric data cells, usually with buttons above for 'Measures', 'Flip axis', etc.)
        2. Are the rows grouped by Product names (e.g., 'Cabinet', 'Desk', 'Chair') rather than stages (New, Done) or teams?
        
        Respond with JSON:
        {
            "is_pivot_view": true/false,
            "grouped_by_product": true/false
        }
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("is_pivot_view"):
                    vlm_score += 10
                    feedback_parts.append("VLM confirms Pivot view active.")
                if parsed.get("grouped_by_product"):
                    vlm_score += 10
                    feedback_parts.append("VLM confirms rows are Products.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score

    # Pass threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }