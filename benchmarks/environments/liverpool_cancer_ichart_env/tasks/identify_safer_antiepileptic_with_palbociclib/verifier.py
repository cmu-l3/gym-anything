#!/usr/bin/env python3
"""
Verifier for identify_safer_antiepileptic_with_palbociclib task.

Verification Strategy:
1. File Verification (70 pts):
   - Check if report exists and was created during task.
   - Parse report for drug names and colors.
   - Verify pharmacological logic (Carbamazepine should be Red/Orange, Gabapentin Green/Yellow).
   - Verify "Safer Option" matches the colors found.

2. VLM Trajectory Verification (30 pts):
   - Sample frames from the trajectory.
   - Verify agent actually looked up Palbociclib.
   - Verify agent saw the interaction results for both drugs.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_antiepileptic_safety(traj, env_info, task_info):
    """
    Verify the agent correctly identified the safer anti-epileptic drug.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Retrieve Result File
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 2. File-Based Verification (70 Points)
    # ================================================================
    report_exists = result.get("report_exists", False)
    created_during = result.get("file_created_during_task", False)
    content = result.get("report_content", "")

    if not report_exists:
        feedback_parts.append("Report file not found.")
        return {"passed": False, "score": 0, "feedback": "Report file missing"}
    
    if not created_during:
        feedback_parts.append("Report file timestamp is old (pre-task).")
        # Continue but penalty
    else:
        score += 10
        feedback_parts.append("Report created during task.")

    # Parse Content
    # Expected format:
    # Cancer Drug: Palbociclib
    # Carbamazepine: [COLOR]
    # Gabapentin: [COLOR]
    # Safer Option: [Name]
    
    content_lower = content.lower()
    
    has_palbo = "palbociclib" in content_lower
    has_carba = "carbamazepine" in content_lower
    has_gaba = "gabapentin" in content_lower
    
    if has_palbo and has_carba and has_gaba:
        score += 10
        feedback_parts.append("Report contains all required drug names.")
    else:
        feedback_parts.append(f"Report missing drugs (Palbo:{has_palbo}, Carba:{has_carba}, Gaba:{has_gaba}).")

    # Extract Colors
    valid_colors = ["red", "orange", "amber", "yellow", "green", "grey", "gray"]
    
    # Helper to find color in a line
    def extract_color(text, drug_name):
        lines = text.split('\n')
        for line in lines:
            if drug_name in line.lower():
                for color in valid_colors:
                    if color in line.lower():
                        return color
        return None

    carba_color = extract_color(content, "carbamazepine")
    gaba_color = extract_color(content, "gabapentin")
    
    # Scoring colors (Pharmacology Check)
    # Carbamazepine + Palbociclib -> CYP3A4 Inducer -> RED or ORANGE
    carba_correct = carba_color in ["red", "orange", "amber"]
    # Gabapentin + Palbociclib -> Renal elim, no CYP -> GREEN or YELLOW
    gaba_correct = gaba_color in ["green", "yellow"]
    
    if carba_correct:
        score += 15
        feedback_parts.append(f"Carbamazepine identified correctly as high risk ({carba_color}).")
    elif carba_color:
        feedback_parts.append(f"Carbamazepine color incorrect/unexpected ({carba_color}).")
    else:
        feedback_parts.append("Could not parse color for Carbamazepine.")
        
    if gaba_correct:
        score += 15
        feedback_parts.append(f"Gabapentin identified correctly as low risk ({gaba_color}).")
    elif gaba_color:
        feedback_parts.append(f"Gabapentin color incorrect/unexpected ({gaba_color}).")
    else:
        feedback_parts.append("Could not parse color for Gabapentin.")

    # Check Safer Option
    safer_line = ""
    for line in content.split('\n'):
        if "safer" in line.lower():
            safer_line = line.lower()
            break
            
    if "gabapentin" in safer_line and "carbamazepine" not in safer_line:
        score += 20
        feedback_parts.append("Correctly identified Gabapentin as the safer option.")
    elif "carbamazepine" in safer_line:
        feedback_parts.append("Incorrectly identified Carbamazepine as safer.")
    else:
        feedback_parts.append("Safer option not clearly identified in report.")

    # ================================================================
    # 3. VLM Trajectory Verification (30 Points)
    # ================================================================
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    You are verifying an agent using the Liverpool Cancer iChart app.
    The agent should have:
    1. Searched for 'Palbociclib'.
    2. Checked interaction with 'Carbamazepine'.
    3. Checked interaction with 'Gabapentin'.
    
    Look at these screenshots.
    - Do you see 'Palbociclib' selected as the cancer drug?
    - Do you see a result screen for 'Carbamazepine'? (Look for Red/Orange banner)
    - Do you see a result screen for 'Gabapentin'? (Look for Green/Yellow banner)
    
    Return JSON:
    {
        "seen_palbociclib": true/false,
        "seen_carbamazepine_result": true/false,
        "seen_gabapentin_result": true/false,
        "interaction_colors_visible": true/false
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("seen_palbociclib"):
            score += 10
            feedback_parts.append("VLM confirmed Palbociclib selection.")
        
        # We give points if EITHER specific drug result was seen, full points for both
        interactions_seen = 0
        if parsed.get("seen_carbamazepine_result"): interactions_seen += 1
        if parsed.get("seen_gabapentin_result"): interactions_seen += 1
        
        if interactions_seen >= 1:
            score += 10
        if interactions_seen == 2:
            score += 10
            feedback_parts.append("VLM confirmed both interaction checks.")
        elif interactions_seen == 0:
            feedback_parts.append("VLM did not clearly see interaction result screens.")
            
    else:
        feedback_parts.append("VLM verification failed to run.")

    return {
        "passed": score >= 60,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }