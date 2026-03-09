#!/usr/bin/env python3
"""
Verifier for audit_travel_meds_cabozantinib task.
"""

import json
import logging
import re
import tempfile
import os
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_travel_meds(traj, env_info, task_info):
    """
    Verifies that the agent checked Cabozantinib interactions for Cyclizine, Loperamide, and Codeine.
    
    Criteria:
    1. Report file exists and was created during the task (20 pts)
    2. Report format and content is correct (all 3 drugs listed) (30 pts)
    3. Reported colors are valid traffic light colors (10 pts)
    4. VLM: Trajectory shows navigation to Cabozantinib (10 pts)
    5. VLM: Trajectory shows checking at least 2 distinct co-medication categories (20 pts)
    6. VLM: Interaction results for specific drugs visible (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from device
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: File Existence & Anti-Gaming ---
    if result_data.get("report_exists", False) and result_data.get("file_created_during_task", False):
        score += 20
        feedback.append("Report file created successfully.")
    elif result_data.get("report_exists", False):
        score += 5
        feedback.append("Report file exists but timestamp is stale (anti-gaming check failed).")
    else:
        feedback.append("Report file not found.")

    # --- Criterion 2 & 3: Content Analysis ---
    raw_content = result_data.get("report_content_raw", "").replace("\\n", "\n")
    valid_colors = ["red", "orange", "yellow", "green", "grey", "gray"]
    
    drugs_found = {
        "cabozantinib": False,
        "cyclizine": False,
        "loperamide": False,
        "codeine": False
    }
    valid_color_count = 0

    # Parse content
    lower_content = raw_content.lower()
    
    if "drug: cabozantinib" in lower_content:
        drugs_found["cabozantinib"] = True
    
    # Regex to find "Drug: Color" pattern
    for drug in ["cyclizine", "loperamide", "codeine"]:
        if drug in lower_content:
            drugs_found[drug] = True
            # Check if a valid color follows
            # Pattern: drugname followed by colon? then color
            match = re.search(rf"{drug}.*?({'|'.join(valid_colors)})", lower_content)
            if match:
                valid_color_count += 1

    # Score content
    if drugs_found["cabozantinib"]:
        score += 10
        feedback.append("Correct cancer drug specified.")
    
    missing_drugs = [d for d, f in drugs_found.items() if not f and d != "cabozantinib"]
    if not missing_drugs:
        score += 20
        feedback.append("All co-medications listed.")
    else:
        score += (3 - len(missing_drugs)) * 5
        feedback.append(f"Missing drugs in report: {', '.join(missing_drugs)}.")

    if valid_color_count == 3:
        score += 10
        feedback.append("All drugs have valid color codes.")
    elif valid_color_count > 0:
        score += valid_color_count * 3
        feedback.append(f"Some color codes valid ({valid_color_count}/3).")

    # --- Criterion 4, 5, 6: VLM Trajectory Verification ---
    frames = sample_trajectory_frames(traj, n=8)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    vlm_prompt = """
    You are verifying an agent's workflow in the Liverpool Cancer iChart app.
    The task is to check 'Cabozantinib' against 'Cyclizine', 'Loperamide', and 'Codeine'.
    
    Analyze the image sequence.
    1. Did the agent select 'Cabozantinib' as the cancer drug? (Look for 'Cabozantinib' header)
    2. Did the agent navigate to different categories? (e.g. Antiemetics, Antidiarrheals, Analgesics)
    3. Are interaction results visible for the specific drugs?
    
    Return JSON:
    {
        "cabozantinib_selected": boolean,
        "categories_navigated": boolean,
        "drugs_checked": ["list of drug names seen in interaction screens"],
        "confidence": "high/medium/low"
    }
    """

    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_data = vlm_res.get("parsed", {})
        
        if vlm_data.get("cabozantinib_selected"):
            score += 10
            feedback.append("VLM confirmed Cabozantinib selection.")
        
        if vlm_data.get("categories_navigated"):
            score += 20
            feedback.append("VLM confirmed category navigation.")
            
        checked = [d.lower() for d in vlm_data.get("drugs_checked", [])]
        visible_count = sum(1 for d in ["cyclizine", "loperamide", "codeine"] if any(d in x for x in checked))
        
        if visible_count >= 2:
            score += 10
            feedback.append("VLM confirmed specific drug checks.")
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback.append("VLM verification unavailable.")
        # Fallback: if text report is perfect, grant partial trust points
        if valid_color_count == 3 and not missing_drugs:
            score += 20
            feedback.append("Granting partial VLM points based on perfect text report.")

    # Final Check
    passed = score >= 70 and drugs_found["cabozantinib"] and len(missing_drugs) == 0
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }