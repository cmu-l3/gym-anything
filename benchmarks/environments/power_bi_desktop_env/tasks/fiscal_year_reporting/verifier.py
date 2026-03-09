#!/usr/bin/env python3
"""
Verifier for fiscal_year_reporting task.

Verification Strategy:
1. PBIX Internal Check (50 pts):
   - File exists and modified during task.
   - Evidence of `DATESYTD` usage with correct year-end parameter ("03-31").
   - Evidence of sorting logic in DataModel.
2. VLM Visual Check (50 pts):
   - Uses the final screenshot (captured by the framework).
   - Verifies the X-axis starts with April and ends with March.
   - Verifies a chart is present.

Total Score: 100
Threshold: 70
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_fiscal_year_reporting(traj, env_info, task_info):
    """
    Verify the fiscal year report task.
    """
    # 1. Setup copy mechanism
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy unavailable"}

    # 2. Retrieve programmatic results from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    vm_result = {}
    try:
        copy_from_env("C:/Users/Docker/Desktop/fiscal_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            vm_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not retrieve/parse result JSON: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Part 1: File & Model Analysis (50 points) ---
    
    # File exists and modified (10 pts)
    if vm_result.get('file_exists') and vm_result.get('file_created_after_start'):
        score += 10
        feedback.append("Report file saved and modified during task.")
    else:
        feedback.append("Report file missing or not saved.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Correct DAX Measure (DATESYTD + Year End) (25 pts)
    # The PowerShell script greps for "DATESYTD" and "03-31" in the binary DataModel
    if vm_result.get('contains_datesytd'):
        score += 15
        feedback.append("DATESYTD function found in model.")
    else:
        feedback.append("DATESYTD function NOT found.")

    if vm_result.get('contains_year_end_param'):
        score += 10
        feedback.append("Correct fiscal year-end parameter (03-31) detected.")
    else:
        feedback.append("Fiscal year-end parameter missing/incorrect.")

    # Sorting Logic (15 pts)
    # Heuristic check for sort/index columns
    if vm_result.get('contains_sort_column_logic'):
        score += 15
        feedback.append("Sort column/Index logic detected in model.")
    else:
        feedback.append("Warning: Could not confirm 'Sort By Column' usage from file (will rely on visual check).")

    # --- Part 2: Visual Verification via VLM (50 points) ---
    
    # Get screenshot
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        You are verifying a Power BI report task.
        
        TASK: Create a chart showing Revenue by Month, sorted by Fiscal Year (April to March).
        
        Look at the screenshot:
        1. Is there a bar or column chart visible?
        2. Look at the X-axis labels. Do they start with "Apr" (or April) and follow chronological order (May, Jun...) ending in "Mar" (or March)?
        3. Or does it start with Jan (Calendar year)?
        
        JSON Response format:
        {
            "chart_visible": true/false,
            "starts_with_april": true/false,
            "ends_with_march": true/false,
            "is_sorted_chronologically": true/false,
            "explanation": "..."
        }
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            
            if vlm_resp.get('success'):
                parsed = vlm_resp.get('parsed', {})
                
                if parsed.get('chart_visible'):
                    score += 10
                    feedback.append("Chart visual confirmed.")
                    
                    if parsed.get('starts_with_april') and parsed.get('ends_with_march'):
                        score += 40
                        feedback.append("Visual verification PASSED: Chart is sorted April -> March.")
                    elif parsed.get('starts_with_april'):
                        score += 20
                        feedback.append("Chart starts with April but end month unclear.")
                    else:
                        feedback.append("Visual verification FAILED: Chart does not start with April.")
                else:
                    feedback.append("No chart detected in final screenshot.")
            else:
                feedback.append(f"VLM Analysis failed: {vlm_resp.get('error')}")
                # Fallback: if we found sort logic in model, give partial credit
                if vm_result.get('contains_sort_column_logic'):
                    score += 20
                    feedback.append("Fallback: Awarding partial points for model sort logic.")
        except Exception as e:
            feedback.append(f"Verification error: {str(e)}")
    else:
        feedback.append("No final screenshot available for visual verification.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }