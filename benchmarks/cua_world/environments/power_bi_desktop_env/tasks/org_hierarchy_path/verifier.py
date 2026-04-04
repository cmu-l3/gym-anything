#!/usr/bin/env python3
"""
Verifier for org_hierarchy_path task.

Scoring (100 points total):
1. File Saved (10 pts): Report exists and was modified during task.
2. PATH Function Usage (25 pts): Verification that DAX PATH logic was used.
3. Hierarchy Columns (25 pts): "Level 1 Leader", "Level 2", "Level 3" found in layout.
4. Matrix Visual (15 pts): pivotTable visual type exists.
5. Drill-down Config (10 pts): Hierarchy fields detected in usage.
6. VLM Verification (15 pts): Visual check of the matrix structure.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logger = logging.getLogger(__name__)

def verify_org_hierarchy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve Programmatic Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env("C:/Users/Docker/Desktop/org_hierarchy_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig', errors='replace') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: File Existence (10 pts)
    if result.get('file_exists') and result.get('file_created_after_start'):
        score += 10
        feedback.append("✅ Report saved successfully.")
    else:
        feedback.append("❌ Report file missing or old.")

    # Criterion 2: DAX PATH Logic (25 pts)
    # Note: Binary search in powershell might be flaky for compressed models. 
    # If columns are named "OrgPath", we give partial credit even if "PATH(" string missed.
    columns = result.get('columns_found', [])
    dax_found = result.get('dax_path_function_found', False)
    
    if dax_found:
        score += 25
        feedback.append("✅ DAX PATH function usage detected.")
    elif "OrgPath" in columns:
        score += 15 # Partial credit for correct column name implying logic
        feedback.append("⚠️ 'OrgPath' column found, but DAX formula unverified (Partial Credit).")
    else:
        feedback.append("❌ No evidence of PATH function usage.")

    # Criterion 3: Hierarchy Columns (25 pts)
    # Need Level 1, Level 2, Level 3
    levels_found = sum(1 for c in columns if "Level" in c and "Leader" in c)
    if levels_found >= 3:
        score += 25
        feedback.append("✅ Hierarchy level columns found.")
    elif levels_found > 0:
        score += 10
        feedback.append(f"⚠️ Only {levels_found}/3 hierarchy columns found.")
    else:
        feedback.append("❌ Hierarchy columns missing.")

    # Criterion 4: Matrix Visual (15 pts)
    if result.get('matrix_visual_found'):
        score += 15
        feedback.append("✅ Matrix visual present.")
    else:
        feedback.append("❌ Matrix visual not found.")

    # Criterion 5: Drill-down Config (10 pts)
    if result.get('hierarchy_fields_found'):
        score += 10
        feedback.append("✅ Hierarchy fields appear to be used in visual.")
    else:
        feedback.append("❌ Hierarchy fields not detected in visual layout.")

    # Criterion 6: VLM Verification (15 pts)
    # Check screenshot for a Matrix with +/- icons or indented layout
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = """
        Analyze this Power BI screenshot.
        1. Is there a Matrix or Table visual visible?
        2. Does it show a hierarchy (e.g., indented names, +/- expand buttons, or multiple levels like 'Sanchez' -> 'Duffy')?
        3. Do you see salary numbers (e.g. currency values)?
        
        Respond JSON: {"matrix_visible": bool, "hierarchy_visible": bool, "values_visible": bool}
        """
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        parsed = vlm_res.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('matrix_visible'): vlm_score += 5
        if parsed.get('hierarchy_visible'): vlm_score += 10
        
        score += vlm_score
        if vlm_score > 0:
            feedback.append(f"✅ VLM verified visual appearance ({vlm_score} pts).")
        else:
            feedback.append("❌ VLM did not see a hierarchy matrix.")
    else:
        feedback.append("⚠️ No screenshot available for VLM verification.")

    return {
        "passed": score >= 70,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }