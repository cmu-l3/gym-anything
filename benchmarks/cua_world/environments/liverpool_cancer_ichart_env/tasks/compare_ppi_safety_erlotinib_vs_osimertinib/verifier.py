#!/usr/bin/env python3
"""
Verifier for Compare PPI Safety: Erlotinib vs Osimertinib.

Checks:
1. Report file existence and freshness (anti-gaming).
2. Report content accuracy (Colors for both drugs + Recommendation).
3. Evidence of multi-drug selection (via Screenshot VLM).
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ppi_comparison(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})

    # 1. Retrieve Result JSON from Android container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_log = []

    # 2. Verify Report Existence & Timestamp
    if not result_data.get("report_exists", False):
        return {"passed": False, "score": 0, "feedback": "Report file /sdcard/ppi_switch_recommendation.txt not found."}
    
    if not result_data.get("file_created_during_task", False):
        feedback_log.append("WARNING: Report file was not modified during the task interval.")
        # We penalize heavily for stale data
        score += 0
    else:
        score += 10
        feedback_log.append("Report file created during task.")

    # 3. Analyze Report Content (Regex)
    content = result_data.get("report_content", "").lower()
    
    # Check Erlotinib Color (Expect Red or Orange)
    erlotinib_safe = False
    if "erlotinib" in content:
        if re.search(r"erlotinib.*?color.*?(red|orange)", content, re.DOTALL):
            score += 20
            feedback_log.append("Correctly identified Erlotinib interaction (Red/Orange).")
            erlotinib_safe = True
        else:
            feedback_log.append("Incorrect color for Erlotinib (Expected Red/Orange).")
    else:
        feedback_log.append("Erlotinib not mentioned in report.")

    # Check Osimertinib Color (Expect Green or Yellow)
    osimertinib_safe = False
    if "osimertinib" in content:
        # Note: Depending on app version, it might be Green or Yellow (caution but usually safer).
        # Ground truth says Green/Yellow.
        if re.search(r"osimertinib.*?color.*?(green|yellow)", content, re.DOTALL):
            score += 20
            feedback_log.append("Correctly identified Osimertinib interaction (Green/Yellow).")
            osimertinib_safe = True
        else:
            feedback_log.append("Incorrect color for Osimertinib (Expected Green/Yellow).")
    else:
        feedback_log.append("Osimertinib not mentioned in report.")

    # Check Recommendation (Expect Osimertinib)
    rec_safe = False
    if re.search(r"safer.*?(osimertinib)", content, re.DOTALL):
        score += 20
        feedback_log.append("Correctly recommended Osimertinib.")
        rec_safe = True
    else:
        feedback_log.append("Did not correctly recommend Osimertinib as the safer choice.")

    # 4. Verify Screenshot via VLM
    # We want to see evidence that BOTH drugs were compared in a table/list
    screenshot_score = 0
    if result_data.get("screenshot_exists", False):
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env("/sdcard/ppi_comparison_table.png", temp_img.name)
            
            prompt = (
                "Analyze this screenshot from the Liverpool Cancer iChart app. "
                "Does it show a list or table containing BOTH 'Erlotinib' and 'Osimertinib' "
                "along with 'Omeprazole'? Return JSON: {\"both_drugs_visible\": bool, \"omeprazole_visible\": bool}"
            )
            
            vlm_resp = query_vlm(image=temp_img.name, prompt=prompt)
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("both_drugs_visible", False):
                    screenshot_score += 20
                    feedback_log.append("Screenshot confirms simultaneous comparison.")
                elif parsed.get("omeprazole_visible", False):
                    screenshot_score += 10
                    feedback_log.append("Screenshot shows Omeprazole but missing one or both cancer drugs.")
                else:
                    feedback_log.append("Screenshot does not clearly show the relevant drugs.")
            
            os.unlink(temp_img.name)
        except Exception as e:
            feedback_log.append(f"VLM verification failed: {str(e)}")
    else:
        feedback_log.append("Comparison screenshot not found.")

    score += screenshot_score
    
    # 5. Workflow Efficiency Bonus
    # If they did it in one go (evidenced by the single screenshot with both), they get full points.
    # We implicitly rewarded this in the screenshot section. 
    # We can add a small bonus if the report format is strictly followed.
    if "interaction 1" in content and "interaction 2" in content:
        score += 10
        feedback_log.append("Report format followed.")

    passed = (erlotinib_safe and osimertinib_safe and rec_safe and score >= 70)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_log)
    }