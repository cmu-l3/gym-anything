#!/usr/bin/env python3
"""
Verifier for select_safer_insomnia_medication_crizotinib task.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_select_safer_insomnia_medication_crizotinib(traj, env_info, task_info):
    """
    Verifies that the agent correctly identified drug interaction severities and made the safer recommendation.
    
    Expected logic:
    - Crizotinib + Zopiclone -> Interaction likely (Amber/Red) due to CYP3A4 inhibition.
    - Crizotinib + Lorazepam -> Interaction unlikely (Green/Yellow) due to glucuronidation.
    - Recommendation -> Lorazepam.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Result JSON from Android environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. File Existence & Anti-Gaming Checks (20 points)
    if not result_data.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Report file not created"}
    
    score += 10
    feedback_parts.append("Report file created")

    if result_data.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("WARNING: File timestamp predates task start")

    # 3. Content Analysis (50 points)
    content = result_data.get("file_content", "").lower()
    
    # Regex patterns to extract findings
    # Format expected: "Crizotinib + Zopiclone: [Color]"
    zopiclone_match = re.search(r"zopiclone.*?(red|amber|orange|yellow|green|grey)", content)
    lorazepam_match = re.search(r"lorazepam.*?(red|amber|orange|yellow|green|grey)", content)
    recommendation_match = re.search(r"recommend.*?(zopiclone|lorazepam)", content)

    # Verify Zopiclone Color (Amber/Red/Orange expected for CYP3A4 inhibition interaction)
    # Crizotinib is a moderate CYP3A4 inhibitor; Zopiclone is a substrate. 
    # The app likely flags this as Amber or Red.
    zopiclone_score = 0
    if zopiclone_match:
        color = zopiclone_match.group(1)
        if color in ["amber", "red", "orange"]:
            zopiclone_score = 20
            feedback_parts.append(f"Zopiclone correctly identified as high risk ({color})")
        else:
            feedback_parts.append(f"Zopiclone identified as {color} (expected Amber/Red)")
    else:
        feedback_parts.append("Could not parse Zopiclone result")
    score += zopiclone_score

    # Verify Lorazepam Color (Green/Yellow expected for safer option)
    lorazepam_score = 0
    if lorazepam_match:
        color = lorazepam_match.group(1)
        if color in ["green", "yellow", "grey"]: # Grey often means "no data/no interaction"
            lorazepam_score = 20
            feedback_parts.append(f"Lorazepam correctly identified as low risk ({color})")
        else:
            feedback_parts.append(f"Lorazepam identified as {color} (expected Green/Yellow)")
    else:
        feedback_parts.append("Could not parse Lorazepam result")
    score += lorazepam_score

    # Verify Recommendation
    rec_score = 0
    if recommendation_match:
        rec_drug = recommendation_match.group(1)
        if rec_drug == "lorazepam":
            rec_score = 10
            feedback_parts.append("Correctly recommended Lorazepam")
        else:
            feedback_parts.append(f"Incorrectly recommended {rec_drug}")
    else:
        feedback_parts.append("Recommendation not found in report")
    score += rec_score

    # 4. VLM Trajectory Verification (30 points)
    # Check if agent actually looked at the screens
    from gym_anything.vlm import query_vlm
    
    frames = sample_trajectory_frames(traj, n=6)
    vlm_prompt = """
    Analyze these screenshots from the Liverpool Cancer iChart app.
    I need to verify if the user checked interactions for Crizotinib with Zopiclone AND Lorazepam.
    
    Look for:
    1. 'Crizotinib' selected as the cancer drug.
    2. 'Zopiclone' selected/visible in co-medications list or interaction result.
    3. 'Lorazepam' selected/visible in co-medications list or interaction result.
    4. Traffic light colors visible (Red/Amber/Green/Yellow).
    
    Return JSON:
    {
        "crizotinib_seen": boolean,
        "zopiclone_seen": boolean,
        "lorazepam_seen": boolean,
        "interaction_results_viewed": boolean
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    vlm_score = 0
    if vlm_data.get("crizotinib_seen", False): vlm_score += 5
    if vlm_data.get("zopiclone_seen", False): vlm_score += 10
    if vlm_data.get("lorazepam_seen", False): vlm_score += 10
    if vlm_data.get("interaction_results_viewed", False): vlm_score += 5
    
    score += vlm_score
    feedback_parts.append(f"VLM verification score: {vlm_score}/30")

    # Pass logic
    # Must have the file, reasonable text content, and correct recommendation
    passed = (score >= 70) and (rec_score > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }