#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_project_lifecycle_tracking(traj, env_info, task_info):
    """
    Verifies the Construction Status Power BI report.
    
    Criteria:
    1. File Saved (10 pts)
    2. Data Model: Measure 'Budget_Utilization_Pct' exists (15 pts)
    3. Data Model: 'Stage' column uses Sort By Column (30 pts) - CRITICAL
    4. Report: Bar Chart and Table visuals exist (15 pts)
    5. Report: Conditional Formatting applied (15 pts)
    6. VLM Check: Visual confirmation of order and coloring (15 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Check (10 pts)
    if result.get("file_exists"):
        score += 10
        feedback.append("File 'Construction_Status.pbix' found.")
    else:
        return {"passed": False, "score": 0, "feedback": "File 'Construction_Status.pbix' not found."}

    # 2. Measure Check (15 pts)
    measures = [m.lower() for m in result.get("measures", [])]
    if "budget_utilization_pct" in measures:
        score += 15
        feedback.append("Measure 'Budget_Utilization_Pct' created.")
    else:
        feedback.append("Measure 'Budget_Utilization_Pct' MISSING.")

    # 3. Sort By Column Check (30 pts)
    has_sort = result.get("has_sort_by_column", False)
    if has_sort:
        score += 30
        feedback.append("Correctly applied 'Sort By Column' to Stage.")
    else:
        feedback.append("FAILED to apply 'Sort By Column' to Stage. Visuals will likely sort alphabetically.")

    # 4. Visuals Check (15 pts)
    visuals = result.get("visuals", [])
    has_bar = any("bar" in v.lower() or "column" in v.lower() for v in visuals)
    has_table = any("table" in v.lower() for v in visuals)
    
    if has_bar and has_table:
        score += 15
        feedback.append("Bar Chart and Table visuals present.")
    elif has_bar or has_table:
        score += 7
        feedback.append("One of the required visuals (Bar/Table) is missing.")
    else:
        feedback.append("Required visuals (Bar/Table) not found.")

    # 5. Conditional Formatting Check (15 pts)
    if result.get("conditional_formatting", False):
        score += 15
        feedback.append("Conditional formatting logic detected.")
    else:
        feedback.append("No conditional formatting detected.")

    # 6. VLM Verification (15 pts)
    # We use VLM to visually confirm the sort order is NOT alphabetical
    # Alphabetical: Complete, Finishing, Foundation, Framing, Planning, Systems
    # Logical: Planning, Foundation, Framing, Systems, Finishing, Complete
    # If the first bar is "Planning" or "1-Planning", it's correct. If "Complete", it's wrong.
    
    from gym_anything.vlm import get_final_screenshot, query_vlm
    final_img = get_final_screenshot(traj)
    
    vlm_score = 0
    if final_img:
        prompt = """
        Analyze this Power BI report screenshot.
        1. Look at the Bar Chart showing Project Stages. 
        2. What is the label of the FIRST (top or left) bar? 
        3. Do the stages appear to be in a logical construction order (Planning -> Foundation...) or Alphabetical order (Complete -> Finishing...)?
        4. Is there a table with red text or red background on some numbers?
        
        Return JSON:
        {
            "sort_order": "logical" | "alphabetical" | "unknown",
            "red_formatting_visible": true | false
        }
        """
        try:
            vlm_res = query_vlm(image=final_img, prompt=prompt)
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("sort_order") == "logical":
                vlm_score += 10
                feedback.append("VLM confirms logical sort order.")
            elif parsed.get("sort_order") == "alphabetical":
                feedback.append("VLM sees ALPHABETICAL sort order (incorrect).")
            
            if parsed.get("red_formatting_visible"):
                vlm_score += 5
                feedback.append("VLM confirms conditional formatting colors.")
                
        except Exception as e:
            feedback.append(f"VLM check failed: {e}")
    
    score += vlm_score

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }